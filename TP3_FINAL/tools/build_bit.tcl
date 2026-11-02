# Uso: vivado -mode batch -source build_bit.tcl -tclargs <top> <mhz> <outdir> <wiz|mmcm> <xdc> <defines> <archivo.v> ...
#   <defines>: nombres separados por coma para synth_design -verilog_define (por ejemplo CPU_STUB), o "-" si no hay.
# Flujo non-project (D-13): el Clock Wizard clk_wiz_0 se crea en memoria con salida <mhz> (puertos clk_in1,
# clk_out1, locked; sin reset), y el top recibe CLOCK_FREQ = <mhz>·10^6 por -generic.
# Nada de esto se versiona fuera de este script.
set top   [lindex $argv 0]
set mhz   [lindex $argv 1]
set out   [lindex $argv 2]
set clk   [lindex $argv 3]
set xdc   [lindex $argv 4]
set defs  [lindex $argv 5]
set files [lrange $argv 6 end]
set part  xc7a35tcpg236-1
set freq  [expr {$mhz * 1000000}]
set div   [format %.3f [expr {1000.0 / $mhz}]]
set vdefs [list CLKOUT0_DIVIDE=$div]
if {$defs ne "-"} {
    foreach d [split $defs ,] { lappend vdefs $d }
}

file mkdir $out
create_project -in_memory -part $part
set_property target_language Verilog [current_project]

set incdirs {}
foreach f $files {
    read_verilog $f
    lappend incdirs [file dirname $f]
}
read_xdc $xdc

if {$clk eq "wiz"} {
    file mkdir $out/ip
    create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_0 -dir $out/ip
    set_property -dict [list \
        CONFIG.PRIM_IN_FREQ {100.000} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $mhz \
        CONFIG.USE_RESET {false} \
        CONFIG.USE_LOCKED {true}] [get_ips clk_wiz_0]
    set_property generate_synth_checkpoint false [get_files clk_wiz_0.xci]
    generate_target all [get_ips clk_wiz_0]
} else {
    # clk_gen.v ya está en $files; acá solo falta restringir el reloj de entrada.
    set fh [open $out/clk100.xdc w]
    puts $fh "create_clock -period 10.000 -name sys_clk_pin \[get_ports i_clk100\]"
    close $fh
    read_xdc $out/clk100.xdc
}

synth_design -top $top -part $part -generic CLOCK_FREQ=$freq \
    -verilog_define $vdefs -include_dirs [lsort -unique $incdirs]

# Tiene que haber al menos 2 relojes: el de entrada y el de salida del Wizard/MMCM.
if {[llength [get_clocks]] < 2} {
    error "build_bit: relojes insuficientes: [get_clocks]"
}

opt_design
place_design
route_design

report_timing_summary -file $out/timing.rpt
report_utilization    -file $out/util.rpt
report_clocks         -file $out/clocks.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
write_bitstream -force $out/$top.bit

set fh [open $out/summary.txt w]
puts $fh "TOP=$top MHZ=$mhz CLK=$clk WNS=$wns WHS=$whs"
close $fh

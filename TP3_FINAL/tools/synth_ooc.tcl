# Uso: vivado -mode batch -source synth_ooc.tcl -tclargs <top> <outdir> <archivo.v> ...
set top   [lindex $argv 0]
set out   [lindex $argv 1]
set files [lrange $argv 2 end]
set part  xc7a35tcpg236-1
file mkdir $out
create_project -in_memory -part $part
set incdirs [list \
    [file normalize [file join [file dirname [info script]] ../VIVADO/TP_FINAL/rtl/common]] \
    [file normalize [file join [file dirname [info script]] ../VIVADO/TP_FINAL/rtl/debug]]]
foreach f $files {
    read_verilog $f
    lappend incdirs [file dirname $f]
}
synth_design -top $top -part $part -mode out_of_context -include_dirs [lsort -unique $incdirs]
report_utilization -file $out/util.rpt
report_methodology -file $out/methodology.rpt

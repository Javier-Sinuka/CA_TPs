set top [lindex $argv 0]
set output [lindex $argv 1]
set sources [lrange $argv 2 end]
set part xc7a35tcpg236-1

file mkdir $output
create_project -in_memory -part $part
set include_dirs {}
foreach source $sources {
    lappend include_dirs [file dirname $source]
}
set_property include_dirs [lsort -unique $include_dirs] [current_fileset]
foreach source $sources {
    if {[file extension $source] ne ".vh"} {
        read_verilog $source
    }
}
synth_design -top $top -part $part -mode out_of_context -include_dirs [lsort -unique $include_dirs]
if {[llength [get_ports -quiet i_clock]] > 0} {
    create_clock -name i_clock -period 10.000 [get_ports i_clock]
}
report_utilization -file [file join $output util.rpt]
report_methodology -file [file join $output methodology.rpt]

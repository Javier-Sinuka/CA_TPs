proc collect_files {directory extensions} {
    set result {}
    foreach path [glob -nocomplain -directory $directory *] {
        if {[file isdirectory $path]} {
            lappend result {*}[collect_files $path $extensions]
        } elseif {[file extension $path] in $extensions} {
            lappend result $path
        }
    }
    return [lsort $result]
}

set tp [file normalize [file join [file dirname [info script]] ..]]
set root [file dirname $tp]
set output [file join $tp VIVADO TP_FINAL]
if {[llength $argv]} {
    set output [file normalize [lindex $argv 0]]
}
set rtl [file join $tp VIVADO TP_FINAL rtl]
set tb [file join $tp VIVADO TP_FINAL tb]
create_project TP_FINAL $output -force -part xc7a35tcpg236-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files -norecurse [collect_files $rtl {.v .vh}]
set_property include_dirs [list [file join $rtl common] [file join $rtl debug]] [get_filesets sources_1]
set_property top top_debug [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $tp constraints basys3_debug.xdc]
add_files -fileset sim_1 -norecurse [collect_files $tb {.sv .svh .hex}]
add_files -fileset sim_1 -norecurse [collect_files [file join $tp programs] {.hex}]
set_property include_dirs [list [file join $rtl common] [file join $rtl debug] [file join $tb common] [file join $tb debug]] [get_filesets sim_1]
set_property top tb_system_cpu_smoke [get_filesets sim_1]
set_property top_auto_set false [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property -dict [list xsim.simulate.xsim.more_options [list -testplusarg ROOT=$root/]] [get_filesets sim_1]
set resources [concat \
    [collect_files [file join $tp doc] {.md .dot .svg}] \
    [collect_files [file join $tp tools] {.py .tcl}] \
    [collect_files [file join $tp programs] {.s .json}] \
    [collect_files [file join $tp sw tests] {.py}]]
add_files -fileset utils_1 -norecurse $resources
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "PASS project: [get_property PART [current_project]], top_debug, tb_system_cpu_smoke, CPU real, MMCM 50 MHz"
close_project

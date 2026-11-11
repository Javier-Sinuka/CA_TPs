# Uso: vivado -mode batch -source program.tcl -tclargs <archivo.bit>
set bit [lindex $argv 0]
if {![file isfile $bit]} {
    error "Bitstream not found: $bit"
}
open_hw_manager
try {
    connect_hw_server
    open_hw_target
    set devices [get_hw_devices -quiet -filter {PART =~ xc7a35t*}]
    if {[llength $devices] != 1} {
        error "Expected one XC7A35T device, found [llength $devices]"
    }
    set dev [lindex $devices 0]
    current_hw_device $dev
    refresh_hw_device -update_hw_probes false $dev
    set_property PROGRAM.FILE $bit $dev
    program_hw_devices $dev
    puts "PASS program: $dev, $bit"
} finally {
    catch {close_hw_target}
    catch {disconnect_hw_server}
    close_hw_manager
}

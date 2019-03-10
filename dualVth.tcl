proc dualVth {args} {
	parse_proc_arguments -args $args results
	set savings $results(-savings)
	suppress_message LNK-041

	set start_power 0
	set ncells 0
	report_power > pow_rpt_temp.txt
	set fID [open "pow_rpt_temp.txt" r]
	while { [gets $fID line] >= 0 } {
#Get the initial leakage power
		if { [regexp -line {Cell Leakage Power} $line mymatch ] > 0 } {
			set mystring $line
			scan $mystring " Cell Leakage Power = %f" start_power
			break
		}
	}

	close $fID
	set leak_power $start_power
	set cell_list [get_cells]
	set name_list [list]
	set path_list [list]
	set full_list [list]

	foreach_in_collection row $cell_list {
		set cell [get_attribute $row full_name]
		lappend name_list $cell
		set row_path [get_timing_paths -through "${cell}/Z"]
		lappend path_list $row_path
		set slack_time [get_attribute $row_path slack]
		set my_cell $cell
		lappend my_cell $slack_time
		lappend full_list $my_cell
		set ncells [expr $ncells + 1]
	}

#At this point we have a collection: each element has 2 entries: CellName, Slack
#Sort the collection according to the slack (index 1)
	set sorted_full_list [lsort -decreasing -ascii -index 1 $full_list ]

#Creating a list with only the names of the cells, sorted by slack
	set i 0
	set sorted_name_list [list]
	while {$i < $ncells} {
		lappend sorted_name_list [lindex [lindex $sorted_full_list $i] 0]
		set i [expr $i + 1]
	}

#old_pos = pointer to the last scanned cell
	set old_pos 0
	set mygoal 1

#If we want a saving < 40%, scan less cells at a time
	set k 0
	if { $savings < 0 || $savings > 1 } {
		#savings is supposed to be between 0 and 1
		puts "Please, insert a valid value for savings."
		return;
	} else {
		if {$savings < 0.4} {
			set k 0.05
			#Otherwise scan more cells at a time
		} else {
			set k 0.1
		}
	}

	set iterations [expr $k * $savings * $ncells]
	#set forbidden_gate_type [list]
	while { $leak_power > [expr $start_power*(1-$savings)] } {
		set j 0
		while {$j < $iterations} {
			#Get the reference name of the gate in the tech library
			set gate_type [get_attribute -class cell [lindex $sorted_name_list [expr $old_pos + $j]] ref_name] 
			
			#Substitute **_LL_** with **_LH_**
			set old_cell [split $gate_type {_}]
			set new_cell [join [lreplace $old_cell 1 1 "LH"] "_"]
			
			#Control of alternative lib cells: if a $gate_type cell in HVT libray is present, then swap
			#1)make sure that the string is not empty as, giving to get_alternative_lib_cells an empty string would give an error
			set empty [is_empty [lindex $sorted_name_list [expr $old_pos + $j]]]
			if { $empty!=1 } {
				set alternative_cells_list [col2list [get_alternative_lib_cells [lindex $sorted_name_list [expr $old_pos + $j]]]]
				set forbidden [lsearch $alternative_cells_list CORE65LPHVT/$new_cell]
				#2)check that an alternative cell in HVT library is present
			} else {
				set forbidden -1
			}
			
			if {$forbidden != -1} {
				suppress_message NED-045
				suppress_message LNK-041
				suppress_message SEL-003
				
				#Swap LVT -> HVT
				size_cell [lindex $sorted_name_list [expr $old_pos + $j]] CORE65LPHVT_nom_1.20V_25C.db:CORE65LPHVT/$new_cell
			}
			set j [expr $j + 1]
		}

#Update pointer to last scanned cell
	set old_pos [expr $j + $old_pos]

	report_power > pow_rpt_temp.txt
	set fID [open "pow_rpt_temp.txt" r]

	while { [gets $fID line] >= 0 } {
		if { [regexp -line {Cell Leakage Power} $line mymatch ] > 0 } {
			set mystring $line
			scan $mystring " Cell Leakage Power = %f" leak_power
		}
	}
	close $fID

#Check if there are still cells to be scanned
	if { $old_pos >= $ncells -1 } {
		set mygoal 0
		break
	}
	}

#Check if the goal was reached
	set power_gain [expr [expr $start_power - $leak_power] / $start_power]
	report_threshold_voltage_group
	if { $mygoal == 1 } {
		puts "The saving goal is reached : "
	} else {
		puts "The saving goal is too high. The saving reached is : "
	}
	puts $power_gain

return
}

proc is_empty {mystring} {
    expr {![binary scan $mystring c c]}
}
proc col2list { col } {
   set mylist ""
   foreach_in_collection c $col { lappend mylist [get_object_name $c] }
   return $mylist
}

define_proc_attributes dualVth \
-info "Post-Synthesis Dual-Vth cell assignment" \
-define_args \
{
	{-savings "minimum % of leakage savings in range [0, 1]" lvt float required}
}
dualVth -savings 0.90

#exit

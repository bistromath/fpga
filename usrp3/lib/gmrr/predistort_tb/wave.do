onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /predistort_tb/i_tdata
add wave -noupdate /predistort_tb/i_tlast
add wave -noupdate /predistort_tb/i_tvalid
add wave -noupdate /predistort_tb/c_tvalid
add wave -noupdate /predistort_tb/i_tready
add wave -noupdate /predistort_tb/o_tdata
add wave -noupdate /predistort_tb/o_tvalid
add wave -noupdate /predistort_tb/o_tlast
add wave -noupdate /predistort_tb/o_tready
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
set StdArithNoWarnings 1
set NumericStdNoWarnings 1

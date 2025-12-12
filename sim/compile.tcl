set TARGET [lindex $argv 0]
set TB [lindex $argv 1]
set pkg_files [glob ../../${TARGET}/pkg/*]
set src_files [glob ../../${TARGET}/src/*v]
set tb_files [glob ../../${TARGET}/tb/${TB}*v]

exec xvlog -sv {*}$pkg_files {*}$src_files {*}$tb_files

## elab
exec xelab ${TB} -debug typical -log compile.log


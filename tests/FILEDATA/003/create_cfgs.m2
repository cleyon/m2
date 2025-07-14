@comment        This file drives m2 to build a number of configuration files,
@comment        one per host mentioned in file "hosts.dat"
@@
@@
@define cfgfile $1.CFG
@@
@@
@comment        WRITE_CONFIG_FILE
@comment        User command to write a configuration file
@comment        Required parameters: Host name, ID
@@
@newcmd    write_config_file{hostname}{hostid}
@comment                     ^^ These parameter names are referenced
@comment                        in the template file
@local     filename
@define    filename     @cfgfile @{hostname}@
@echo      Writing @filename@
@divert    1
@include   template.txt
@undivert  1            @filename@
@endcmd
@@
@@
@comment        CHECK_CONFIG_FILE
@comment        User command to check config file - compare with *.target
@@
@newcmd    check_config_file{hostname}
@local     filename
@define    filename     @cfgfile @{hostname}@
@syscmd    cmp -s @filename@ @hostname@.target
@if __SYSVAL__ == 0
@echo Check @filename@ OK
@else
@echo Check @filename@ FAILED
@endif
@syscmd rm -f @{filename}
@endcmd
@@
@@
@comment        MAIN PROCEDURE
@@
@comment        Read list of hosts and their IDs from hosts.dat
@@
@array     host_list
@filedata host_list    hosts.dat
@@
@comment        Write a config file for each host in the host_list
@@
@array     fields
@foreach   line         host_list
@local     hostline
@local     hostname
@define    hostline     @host_list[@{line}]@
@comment        Skip comment lines
@if @left hostline 1@ == #
@continue
@else
@split     hostline     fields
@define    hostname     @fields[1]@
@write_config_file{@{hostname}}{@{fields[2]}}
@check_config_file{@{hostname}}
@endif
@next      line

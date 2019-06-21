#!/usr/bin/perl -w

# Copyright (C) 2019 Ole Tange and Free Software Foundation, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <http://www.gnu.org/licenses/>
# or write to the Free Software Foundation, Inc., 51 Franklin St,
# Fifth Floor, Boston, MA 02110-1301 USA

use strict;

my %opt = get_options_hash();

# Reserved words in Python: Replace them
my %reserved = ("return" => "_return",
		"0" => "null");
my @out = <<'_EOS';
#!/usr/bin/python3

# Copyright (C) 2019 Ole Tange and Free Software Foundation, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <http://www.gnu.org/licenses/>
# or write to the Free Software Foundation, Inc., 51 Franklin St,
# Fifth Floor, Boston, MA 02110-1301 USA

import subprocess

_EOS

# Make the function definition
push @out, "def parallel(command=None, args=None, input=None, ";

my @inner;
for my $k (keys %opt) {
    $k =~ s/-/_/g;
    $k =~ s/[:=].*//;
    for my $p (split /\|/, $k) {
	push @inner, ($reserved{$p} || $p)."=None";
    }
}
push @out, join ", ", uniq(@inner);
push @out, "):\n";

# Documentation string
push @out, '    """
    Python wrapper for GNU Parallel

    Use GNU Parallel options with - replaced with _.

    These:

        parallel(command="echo _{}_",args=[["A  B","C  D"],[1,2]],jobs="50%")
        parallel("echo _{}_",args=[["A  B","C  D"],[1,2]],jobs="50%")
        parallel("echo _{}_",[["A  B","C  D"],[1,2]],jobs="50%")

    will all run:

        parallel --jobs 50% echo _{}_ ::: "A  B" "C  D" ::: 1 2

    This:

        parallel(command="echo _{}_",args=["A  B","C  D"],tag=True)

    will run:

        parallel --tag echo _{}_ ::: "A  B" "C  D"

    This:

        parallel(command="echo _{}_",input=b"a\nb\n",keep_order=True)

    will send "a\nb\n" on standard input (stdin) to:

        | parallel --keep-order echo _{}_

    """',"\n";
# Build the command for subprocess.run
push @out, "    option = ['parallel']\n";

for my $k (keys %opt) {
    my $type = "bool";
    if($k =~ s/([:=])(.*)//) {
	my %typeof = ("i" => "int",
		      "f" => "float",
		      "s" => "str");
	$type = $typeof{$2};
    }
    for my $p (split /\|/, $k) {
	my $o = $p;
	$p =~ s/-/_/g;
	push @out, "    if ".($reserved{$p} || $p)." is not None:\n";
	# --long-option? or -s hort?
	my $dashes = ($o =~ /../) ? "--" : "-";
	if($type eq "bool") {
	    push @out, "        option.extend(['$dashes$o'])\n";
	}
	if($type eq "str" or $type eq "float" or $type eq "int") {
	    push @out, "        option.extend(['$dashes$o',".($reserved{$p} || $p)."])\n";
	}
    }
}
push @out, map { s/^/    /gm;$_ } join"\n", 
    ("argumentsep = ':::'",
     "if argsep is not None:",
     "    argumentsep = argsep",
     "if arg_sep is not None:",
     "    argumentsep = arg_sep",
     "if command is not None:",
     "    option.append(command)",
     "if args is not None:",
     "    if type(args[0]) is list:",
     "        for a in args:",
     "            option.extend([argumentsep])",
     "            option.extend(map(str,a))",
     "    else:",
     "        option.extend([argumentsep])",
     "        option.extend(map(str,args))",
     "out = subprocess.run(option,input=input,stdout=subprocess.PIPE,stderr=subprocess.PIPE)",
     "return(out.stdout,out.stderr)",
    );
push @out, join "\n", 
    ("",'',
     'print(parallel(command="echo _{}_",args=[["A  B","C  D"],[1,2]],jobs="50%"))',
     'print(parallel(command="echo _{}_",args=["A  B","C  D"],tag=True))',
     'print(parallel(command="echo _{}_",v=True,argsep="f",args=["A  B","C  D"],tag=True))',
     'print(parallel(command="echo _{}_",input=b"a\nb\n",keep_order=True))',
     'print(parallel(args=["pwd","echo foo"]))',
     ''
    );

print @out;

sub get_options_hash {
    sub which {
	local $_ = qx{ LANG=C type "$_[0]" };
	my $exit += (s/ is an alias for .*// ||
		     s/ is aliased to .*// ||
		     s/ is a function// ||
		     s/ is a shell function// ||
		     s/ is a shell builtin// ||
		     s/.* is hashed .(\S+).$/$1/ ||
		     s/.* is (a tracked alias for )?//);
	if($exit) {
	    return $_;
	} else {
	    return undef;
	}
    }
    
    my $fullpath = which("parallel");
    my $parallelsource = qx{cat $fullpath};
    # Grap options hash from source
    $parallelsource =~ /([(]"debug.D=s".*?[)])/s || die;
    my $optsource = $1;
    my %opt = eval $optsource;
    return %opt;
}

sub uniq {
    # Remove duplicates and return unique values
    return keys %{{ map { $_ => 1 } @_ }};
}

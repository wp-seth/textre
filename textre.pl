#!/usr/bin/perl
# author: seth
# e-mail: for e-mail-address see http://www.wg-karlsruhe.de/seth/email_address.php 
# description: replaces strings in one or many text-files in-place and recursively using regexps
# textre works in-place
# textre means TEXT-REplacing (REcursively) by Regular Expressions
#
# tab-size: 2

use strict;
use warnings;
use Data::Dumper;
use Cwd;
use Getopt::Long qw(:config bundling);
use Pod::Usage;
use POSIX qw/strftime/;       # format timestamp
use utf8;

$main::VERSION = '3.2.1'; # 2017-05-12

# functions
# =========
# sub syntaxCheck
# 	check cli params
#
# sub loadFile
# 	load file in lines
#
# sub loadFile_charwise
# 	load file charwise
#
# sub log10
# 	log10
#
# sub max
# 	max
#
# sub print_stats
# 	print some stats to stdout
#
# sub saveFile
# 	save string (array) to file
#
# sub search_file
#
# 
# sub tex2umlauts
# 	replace \"a, ..., \ss with umlauts ß
#
# sub text_replacer
#
#
# sub umlauts2tex
# 	replace umlauts and ß with \"a, ..., \ss
#
# sub vernichte_bloede_deutsche_umlaute_und_sz
# 	replace umlauts and ß with ae, ..., ss

# Carp::Always
sub _die {
	die @_ if ref($_[0]);
	if($_[-1] =~ /\n$/s){ # $_ is a read-only value
		my $arg = pop @_;
		$arg =~ s/.*\K at .*? line .*?\n$//s;
		push @_, $arg;
	}
	unshift @_, strftime("%Y-%m-%d %H:%M:%S ", gmtime());
	die &Carp::longmess;
}

sub _warn {
	if($_[-1] =~ /\n$/s){ # $_ is a read-only value
		my $arg = pop @_;
		$arg =~ s/.*\K at .*? line .*?\n$//s;
		push @_, $arg;
	}
	unshift @_, strftime("%Y-%m-%d %H:%M:%S ", gmtime());
	warn &Carp::longmess;
}

$SIG{'__DIE__'} = \&_die;
$SIG{__WARN__}  = \&_warn;

sub syntaxCheck{
	my %params = ( # default cli params
		'charwise'    => 0,    # read charwise (not linewise)
		'filesRE'     => '\\.(?:' . (join '|', qw(
					bas bat bib cc? cfg cgi conf cpp css csv f h hpp html? ini js pas 
					php[3-6]? pl py tex txt vbs vim
				) 
			) . ')$',
		'germanshit'  => 0,   # replace äÄöÖüÜß by ae, ..., ss
		'keep-timestamp' => 0, # keeps timestamp of files
		'lower-case'  => 0,   # tr/[A-Z]/[a-z]/ and some umlauts too
		'lines'       => '.', # lines to work at (reg exp)
		'tex2umlauts' => 0,   # replace "a, \"a, "A, \"A, ..., "s, {\ss} by äÄöÖüÜß
		'upper-case'  => 0,   # tr/[a-z]/[A-Z]/ and some umlauts too
		'umlauts2tex' => 0,   # replace äÄöÖüÜß by \"a, \"A, ..., {\ss}
		'recursively' => 0,   # search subdirs
		'searchRE'    => '',  # search & replace pattern
		'show-default-filesRE' => 0, # show default value for filesRE
		'test'        => 0,   # show result only (without changing files)
		'verbose'     => 1,   # trace; grade of verbosity
		'version'     => 0,   # diplay version and exit
	);
	GetOptions(\%params,
		'charwise|c',
		'filesRE|f=s',
		'germanshit|g',
		'keep-timestamp|k',
		'lines|L=s',
		'lower-case|l',
		'recursively|recursive|r',
		'searchRE|s=s',
		'show-default-filesRE',
		'tex2umlauts',
		'upper-case|u',
		'umlauts2tex',
		'test|t',
		'silent|quiet|q' => sub { $params{'verbose'} = 0;},
		'very-verbose' => sub { $params{'verbose'} = 2;},
		'verbose|v:+',
		# auto_version will not auto make use of 'V'
		'version|V' => sub { Getopt::Long::VersionMessage();}, 
		# auto_help will not auto make use of 'h'
		'help|?|h' => sub { Getopt::Long::HelpMessage(
				-verbose => 99, -sections => "NAME|SYNOPSIS");},
		'man' => sub { pod2usage(-exitval => 0, -verbose => 2);},
	) or pod2usage(-exitval => 2);
	$params{'verbose'} = 1 unless exists $params{'verbose'};
	# check for unvalid combinations
	if($params{'lower-case'} + $params{'upper-case'} == 2){
		die "error: conversion to lowercase _and_ uppercase not possible!\n";
	}
	if($params{'searchRE'} eq '' 
		&& $params{'germanshit'}  == 0
		&& $params{'tex2umlauts'} == 0
		&& $params{'upper-case'}  == 0
		&& $params{'umlauts2tex'} == 0
		&& $params{'lower-case'}  == 0
	){
		pod2usage(-exitval => 2);
	}
	# additional params
	my @additional_params = (0, 0); # number of additional params (min, max);
	if(@ARGV < $additional_params[0] 
			or ($additional_params[1] != -1 and @ARGV > $additional_params[1])){
		if($additional_params[0] == $additional_params[1]){
			print "number of arguments must be exactly $additional_params[0], but is " 
				. (0 + @ARGV) . ".\n";
		}else{
			print "number of arguments must be at least $additional_params[0]"
				. ' and at most ' 
				. ($additional_params[1] == -1 ? 'inf' : $additional_params[1])
				. ", but is " . (0 + @ARGV) . ".\n";
		}
		pod2usage(-exitval => 2);
	}
	if(length($params{'searchRE'}) > 0){
		my $delim = substr($params{'searchRE'}, 0, 1);
		$params{'searchRE'} =~ 
			/^$delim((?:[^\\$delim]*|\\.)*)$delim(?:[^\\$delim]*|\\.)*$delim([a-z]*)$/ or
			die "error: cannot recognize $params{'searchRE'}" 
				. " as a valid regexp like /foo/bar/i\n";
		my $pattern = $1;
		print "pattern for search is '$pattern'.\n" if $params{'verbose'} > 2;
		my $modifiers = $2;
		print "modifiers for search are '$modifiers'.\n" if $params{'verbose'} > 2;
		$modifiers =~ s/[eg]//g; # g- and e-modifiers should not be in find regexp
		$params{'findRE'} = qr/(?$modifiers:$pattern)/;
		if($params{'verbose'} > 1){
			print "used regexp for search is $params{'findRE'}.\n";
		}
	}
	return \%params;
}

{
	package TextRe;
	use Data::Dumper;

	sub new{
		my $class  = shift;
		my $params = shift;
		my $self   = bless {
			'charwise'    => $params->{'charwise'} // 0,
			'counter'     => {
				'dir'           => 1, # number of searched directories
				'files'         => 0, # number of searched files
				'lines'         => 0, # number of searched lines
				'changed_files' => 0, # number of changed files
				'changed_lines' => 0, # number of changed lines
				'changes'       => 0, # number of changes
			},
			'findRE'      => $params->{'findRE'},
			'filesRE'     => $params->{'filesRE'},
			'germanshit'  => $params->{'germanshit'},
			'keep-timestamp' => $params->{'keep-timestamp'},
			'lines'       => $params->{'lines'},
			'lower-case'  => $params->{'lower-case'},
			'recursive'   => $params->{'recursive'},
			'searchRE'    => $params->{'searchRE'},
			'simulation'  => $params->{'simulation'} // 0, 
			'tex2umlauts' => $params->{'tex2umlauts'}, 
			'umlauts2tex' => $params->{'umlauts2tex'}, 
			'upper-case'  => $params->{'upper-case'},
			'verbosity'   => $params->{'verbosity'} // 1,
		}, $class;
		return $self;
	}

	sub loadFile{
		my $self   = shift;
		my $infile = shift;
		open my $INFILE, "<", $infile or die "$!\n";
			my @lines = <$INFILE>;
		close($INFILE);
		return @lines;
	}

	sub loadFile_charwise{
		my $self    = shift;
		my $infile  = shift;
		my $content = '';
		open my $INFILE, "<", $infile or die "$!\n";
			while(!eof($INFILE)){
				$content.=getc($INFILE);
			}
		close($INFILE);
		return $content;
	}

	sub log10{
		my $self = shift;
		my $n    = shift;
		return ($n <= 0) ? 0 : log($n) / log(10);
	}

	sub max{
		my $self = shift;
		my $val0 = shift;
		my $val1 = shift;
		return ($val0 > $val1) ? $val0 : $val1;
	}

	sub msg{
		my $self           = shift;
		my $verb_threshold = shift;
		my $msg            = shift;
		my $type           = shift;
		return 0 if $self->{'verbosity'} < $verb_threshold;
		if(defined $type){
			print "$type: $msg\n";
		}else{
			print "$msg\n";
		}
		return 1;
	}

	sub print_stats{
		my $self    = shift;
		my $counter = $self->{'counter'};
		$self->msg(1, "\nstats:");
		my $searched = ' searched: ' . $counter->{'dir'} . ' dirs, ' . 
			$counter->{'files'} . ' files';
		$searched .= ', '.$counter->{'lines'}.' lines' if $self->{'charwise'} == 0;
		$self->msg(1, $searched);
		my $changed = ' changed:  ' . $counter->{'changed_files'} . ' files, ';
		$changed .= '' . ($self->{'charwise'} == 0 ? 
			$counter->{'changed_lines'} . ' lines' : 
			$counter->{'changes'} . ' places');
		$self->msg(1, $changed);
		if($self->{'lower-case'} or $self->{'upper-case'}){
			$self->msg(1, '(case-changing not included)');
		}
		return 1;
	}

	sub saveFile{
		my $self    = shift;
		my $outfile = shift;
		$self->msg(1, "write file ".$outfile);
		open(my $OUTFILE, ">", $outfile) or die " could not write file. $!\n";
			print $OUTFILE @_;
		close($OUTFILE);
		return 1;
	}

	sub search_file{
		my $self     = shift;
		my $flag_dir_printed = shift;
		my $work_dir = shift;
		my $file     = shift;
		my $searchRE = $self->{'searchRE'};
		my %counter  = ('lines' => 0, 'changed_lines' => 0, 'changes' => 0);
		my @times_bak = (stat $file)[8,9]; # atime, mtime
		if($self->{'charwise'} == 1){
			my $file_content = $self->loadFile_charwise($file);
			my $file_new_content = '';
			my $found_str;
			my $len;
			my $old_pos = 0;
			my $after_matched;
			my $postprocessing = 0 + (
				$self->{'upper-case'} or 
				$self->{'lower-case'} or 
				$self->{'germanshit'} or 
				$self->{'umlauts2tex'} or
				$self->{'tex2umlauts'}
			);
			if($counter{'changes'} == 0 and $postprocessing){
				$self->msg(1, $work_dir . $file);
				$$flag_dir_printed = 1;
			}
			if(defined $searchRE){
				while($file_content =~ /$self->{'findRE'}/gp){
					if($counter{'changes'} == 0 and $postprocessing == 0){
						$self->msg(1, $work_dir . $file);
					}
					$$flag_dir_printed = 1;
					++$counter{'changes'};
					$found_str = ${^MATCH};
					$after_matched = ${^POSTMATCH};
					$len = length($found_str);
					$file_new_content .= substr($file_content, $old_pos, 
						pos($file_content) - $len - $old_pos);
					$old_pos = pos($file_content);
					$self->msg(1, ' orig: ' . ($found_str =~ /\n/ ? "\n": '') . $found_str);
					eval('$found_str =~ s' . $searchRE);
					$self->msg(1, ' new: ' . ($found_str =~ /\n/ ? "\n": '') . $found_str);
					$file_new_content .= $found_str;
				}
				$file_content = $file_new_content;
				$file_content .= $after_matched if defined $after_matched;
			}
			$file_content = uc($file_content) if $self->{'upper-case'};
			$file_content = lc($file_content) if $self->{'lower-case'};
			if($self->{'germanshit'}){
				$self->vernichte_bloede_deutsche_umlaute_und_sz(\$file_content);
			}
			$self->umlauts2tex(\$file_content) if $self->{'umlauts2tex'};
			$self->tex2umlauts(\$file_content) if $self->{'tex2umlauts'};

			if($counter{'changes'} > 0 or $postprocessing){
				$self->msg(1, ' '.$counter{'changes'}.' changes') if defined $searchRE;
				$self->saveFile($file, $file_content) if $self->{'simulation'} == 0;
			}
		}else{ # linewise
			my @lines = $self->loadFile($file);
			my $loglines = $self->max(int($self->log10($#lines + 1) + 1), 2);
			for my $line(@lines){
				++$counter{'lines'};
				if($counter{'lines'} =~ /$self->{'lines'}/){
					my $old_line = $line;
					eval('$line =~ s' . $searchRE) if defined $searchRE;
					$line = uc($line) if $self->{'upper-case'};
					$line = lc($line) if $self->{'lower-case'};
					if($self->{'germanshit'}){
						$self->vernichte_bloede_deutsche_umlaute_und_sz(\$line);
					}
					$self->umlauts2tex(\$line) if $self->{'umlauts2tex'};
					$self->tex2umlauts(\$line) if $self->{'tex2umlauts'};
					if($old_line ne $line){
						$$flag_dir_printed = 1;
						if($self->{'verbosity'} > 0){
							$self->msg(1, $work_dir . $file) if $counter{'changed_lines'} == 0;
							printf('%0'.$loglines.'d: ', $counter{'lines'});
							print $old_line;
							print ' ' x ($loglines-2).'->: '.$line;
						}
						++$counter{'changed_lines'};
					}
				}
			}
			if($counter{'changed_lines'} > 0){
				$self->msg(1, ' ' . $counter{'changed_lines'} . ' lines replaced');
				$self->saveFile($file, @lines) if $self->{'simulation'} == 0;
			}
		}
		if($self->{'simulation'} == 0 && $self->{'keep-timestamp'}){
			utime $times_bak[0], $times_bak[1], $file;
		}
		return \%counter;
	}

	sub test_and_replace{
		my $self     = shift;
		my $text     = shift;
		my $regexp_s = shift;
		my $regexp_r = shift;
		my $strpos = 0;
		my $array_of_changes = [];
		$self->msg(3, "   ".$regexp_s);
		my $numChanges = $$text=~s/$regexp_s/
			my $match = ${^MATCH};
			my $replaced = eval($regexp_r);
			push(@$array_of_changes, [$match, $replaced]);
			$replaced;
			/gpme;
		$numChanges = 0 if $numChanges eq '';
		if($self->{'verbosity'} >= 1){
			for my $repl(@$array_of_changes){
				$self->msg(1, "   ".$repl->[0]);
				$self->msg(1, " ->".$repl->[1]);
			}
		}
		return $numChanges;
	}

	sub tex2umlauts{
		my $self = shift;
		my $str  = shift;
		$$str =~ s/\\?"a/ä/g;
		$$str =~ s/\\?"A/Ä/g;
		$$str =~ s/\\?"o/ö/g;
		$$str =~ s/\\?"O/Ö/g;
		$$str =~ s/\\?"u/ü/g;
		$$str =~ s/\\?"U/Ü/g;
		$$str =~ s/\\?"s|\{\\ss\}/ß/g;
		return 1;
	}

	sub text_replacer{
		my $self        = shift;
		my $working_dir = shift;
		my $counter     = $self->{'counter'};
		my @dirs;
		$self->msg(2, "\n\n  $working_dir/");
		# read_dir and generate renaming_array
		opendir(my $dh, ".") or die "can't open $working_dir: $!";
		my $flag_dir_printed  = 0;
		my @entries = sort(readdir($dh)); # cosmetics
		closedir($dh);
		for my $entry (@entries){
			if(-d $entry){
				push(@dirs, $entry);
			}else{
				if($entry =~ /$self->{'filesRE'}/){
					my $work_dir = ($self->{'verbosity'} == 1 and $flag_dir_printed == 0) ? 
						"\n  $working_dir/\n" : "\n";
					$self->msg(2, "'search:' '$entry'");
					++$counter->{'files'};
					my $counter_present = $self->search_file(
						\$flag_dir_printed, $work_dir, $entry);
					$counter->{'changed_files'} += 
						($counter_present->{'changed_lines'} + $counter_present->{'changes'} > 0);
					$counter->{'lines'}         += $counter_present->{'lines'};
					$counter->{'changed_lines'} += $counter_present->{'changed_lines'};
					$counter->{'changes'}       += $counter_present->{'changes'};
				}else{
					print 'skip:' if $self->{'verbosity'} > 2;
					$self->msg(2, " '$entry'");
				}
			}
		}
		# @dirs = sort(@dirs); # not necessary
		if($self->{'recursive'} == 1){ # search subdirectories
			for my $dir(@dirs){
				if($dir ne '.' and $dir ne '..'){
					chdir($dir);
					++$counter->{'dir'};
					$self->text_replacer($working_dir . '/' . $dir);
					chdir('..');
				}
			}
		}
		return 1;
	}

	sub umlauts2tex{
		my $self = shift;
		my $str  = shift;
		$$str =~ s/ä/\\"a/g;
		$$str =~ s/Ä/\\"A/g;
		$$str =~ s/ö/\\"o/g;
		$$str =~ s/Ö/\\"O/g;
		$$str =~ s/ü/\\"u/g;
		$$str =~ s/Ü/\\"U/g;
		$$str =~ s/ß/{\\ss}/g;
		return 1;
	}

	sub vernichte_bloede_deutsche_umlaute_und_sz{
		my $self = shift;
		my $str  = shift;
		$$str =~ s/ä/ae/g;
		$$str =~ s/Ä/Ae/g;
		$$str =~ s/ö/oe/g;
		$$str =~ s/Ö/Oe/g;
		$$str =~ s/ü/ue/g;
		$$str =~ s/Ü/Ue/g;
		$$str =~ s/ß/ss/g;
		return 1;
	}
}

my $params = syntaxCheck(@ARGV);   # command line parameters
my $textre = TextRe->new({
	'charwise'    => $params->{'charwise'},
	'findRE'      => $params->{'findRE'},
	'filesRE'     => $params->{'filesRE'},
	'germanshit'  => $params->{'germanshit'},
	'keep-timestamp' => $params->{'keep-timestamp'},
	'lines'       => $params->{'lines'},
	'lower-case'  => $params->{'lower-case'},
	'recursive'   => $params->{'recursively'},
	'searchRE'    => $params->{'searchRE'},
	'simulation'  => $params->{'test'},
	'tex2umlauts' => $params->{'tex2umlauts'}, 
	'umlauts2tex' => $params->{'umlauts2tex'}, 
	'upper-case'  => $params->{'upper-case'},
	'verbosity'   => $params->{'verbose'},
});

if($params->{'show-default-filesRE'}){
	$textre->msg(0, $params->{'filesRE'});
}else{
	my $working_dir = cwd;
	$textre->text_replacer($working_dir);
	chdir $working_dir;
	$textre->print_stats();
}

__END__
=encoding utf-8

=head1 NAME

textre ("text replacer with reg exps") replaces strings in a text-file using 
regexps.

=head1 DESCRIPTION

this program lets you change text in one or many text-files in-place and 
recursively by using regular expressions. 

=head1 SYNOPSIS

textre [options]

  -s  --searchRE=s           perl-like search-and-replace pattern 
                              s/findRE/replaceRE/, here written as 
                              -s '/findRE/REPLACE/' where
                               findRE    = search pattern, i.e., text to be replaced
                               replaceRE = replacement
  -f, --filesRE=s            files to search (default = several typical textfiles, 
                              see --show-default-filesRE)
  -c, --charwise             don't read files linewise (default), but charwise
  -k, --keep-timestamp       keep original timestamp (default = no)
  -L, --lines=s              replace only in lines s, s is interpreted as a regexp, 
                              default = all lines
  -r, --recursively          search subdirectories recursively 
                              (default = only present directory)
      --show-default-filesRE show default filesRE and exit
  -t, --test                 don't change anything, just print possible changes to
                              screen

special text modifying / post processing (diff won't be displayed, if -c is set):

  -g, --germanshit           convert äÄöÖüÜß to ae, ..., ss
      --umlauts2tex          convert äÄöÖüÜß to \"a, \"A, ..., {\ss}
      --tex2umlauts          convert "a, \"a, ..., "s, {\ss} to äÄöÖüÜß
  -l, --lower-case           convert all to lower case
  -u, --upper-case           convert all to upper case

meta:

  -V, --version              display version and exit.
  -h, --help                 display brief help
      --man                  display long help (man page)
  -q, --silent               same as --verbose=0
  -v, --verbose              same as --verbose=1 (default)
  -vv,--very-verbose         same as --verbose=2
  -v, --verbose=x            grade of verbosity
                              x=0: no output
                              x=1: default output
                              x=2: much output

some examples:

  textre -s /bratwurst/gruenkohl/i
    replace every occurence of 'bratwurst' (case-insensitive) by 'gruenkoehl' in any
    standard text file.

  textre -s /blutwurst/salat/ -L='^123$'
    replace every occurence of 'blutwurst' by 'salat' in line 123 in any standard 
    text file.

  textre --tex2umlauts -f 'somelatexfile\.tex'
    replace all tex-like umlauts with real unicode umlauts in all files that match 
    .*somelatexfile\.tex.*

  textre -s '/(\d)(\d)/$2$1/' -f='(\.htm|\.txt)$' -r
    switch all pairs of digits in all .htm and .txt files

  note that in windows you have to use double quotes instead of single quotes.

=head1 OPTIONS

=head2 GENERAL

=over 8

=item B<--charwise>, B<-c>

don't read files linewise (default), but charwise in a whole string, such that
replacements across several lines are possible.

=item B<--filesRE>=I<string>, B<-F> I<string>

restrict replacements to files given by regexp I<string> (default ".", i.e., all 
files)

=item B<--keep-timestamp>, B<-k>

keep original timestamp (atime and mtime). default = set mtime to present time

=item B<--lines>=I<regexp>, B<-L> I<regexp>

replace only in lines where the line numbers (starting from 0) match I<regexp>. 
default = '.', i.e., all lines

=item B<--recursive>, B<-r>

search subdirectories recursively

=item B<--searchRE>=I<string>, B<-s> I<string>

perl-like search-and-replace pattern 

  s/findRE/replaceRE/

here written as 

  -s '/findRE/REPLACE/'
	
where

  findRE    = search pattern, i.e., text to be replaced
  replaceRE = replacement

=item B<--show-default-filesRE>

show default value of filesRE and exit.

=item B<--test>, B<-t>

don't change anything, just print possible changes to screen

=back

=head2 POST PROCESSING

param B<--searchRE>=I<string> is not mandatory when using one of these params.

however, if B<--searchRE>=I<string> _and_ one of these params is used, then the 
normal replacement (B<--searchRE>=I<string>) will be done first and the post 
processing will be done afterwards. actually that is the reason, why it is called 
_post_ processing and not _pre_ processing. if you want to change the order, just 
call textre twice, e.g.,

 textre -g ...
 textre -s '/.../.../'

=over 8

=item B<--germanshit>, B<-g>

convert äÄöÖüÜß to ae, ..., ss

=item B<--umlauts2tex>, B<->

convert äÄöÖüÜß to \"a, \"A, ..., {\ss}

=item B<--tex2umlauts>, B<->

convert "a, \"a, ..., "s, {\ss} to äÄöÖüÜß

=item B<--lower-case>, B<-l>

convert all to lower case

=item B<--upper-case>, B<-u>

convert all to upper case

=back

=head2 META

=over 8

=item B<--version>, B<-V>

prints version and exits.

=item B<--help>, B<-h>, B<-?>

prints a brief help message and exits.

=item B<--man>

prints the manual page and exits.

=item B<--verbose>=I<number>, B<-v> I<number>

set grade of verbosity to I<number>. if I<number>==0 then no output
will be given, except hard errors. the higher I<number> is, the more 
output will be printed. default: I<number> = 1.

=item B<--silent, --quiet, -q>

same as B<--verbose=0>.

=item B<--very-verbose, -vv>

same as B<--verbose=3>. you may use B<-vvv> for B<--verbose=4> a.s.o.

=item B<--verbose, -v>

same as B<--verbose=2>.

=back

=head1 LICENCE

Copyright (c) 2008-2017, seth
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

originally written by seth (see https://github.com/wp-seth/textre)

=cut

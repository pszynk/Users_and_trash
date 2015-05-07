#!/usr/bin/perl

use strict;
use warnings;

use Data::Dump qw(dump);
use File::Path qw(make_path);
use File::Find;
use File::Spec;
use File::Copy::Recursive qw(rcopy dircopy rcopy_glob);
use File::Glob qw(:glob :globally);
use File::Xcopy;
use String::Random;
use IO::LockedFile;
use Unix::PasswdFile;
use Unix::GroupFile;
use Safe;

sub create_homedir {
    my $homedir = shift;
    if (! make_path("$homedir", {verbose=>1})) {
        printf STDERR "Cant create directory `$homedir'\n";
        if (! -e "$homedir") {
            return 0;
        }
    }
    return 1;

}

sub move_homedir {
    my ($old_homedir, $new_homedir) = @_;

    if (! -e "$old_homedir") {
        printf STDERR "No such old homedir `$old_homedir'\n";
        return 0;
    }

    rmove("$old_homedir", "$new_homedir");
    return 1;
}

sub copy_to_homedir {
    my ($uid, $gid, $homedir, $copy_from) = @_;
    my @errors = ();
    if (! -e "$homedir") {
        printf STDERR "Direcotry `$homedir' does not exist\n";
        return 0;
    }
#    my $fx = new File::Xcopy;
#    my $from = File::Spec->catfile("$copy_from");
#    my $to = File::Spec->catfile("$homedir");
#    $fx->from_dir("$from");
#    $fx->to_dir("$to");
#    $fx->fn_pat('^\.(\..+|[^\.]+).*');
#    $fx->param('s', 1);
#    $fx->xcopy;
#    #change_user_group_homedir($uid, "-1", $gid, "-1", "$homedir");
#    return 1;
#
#    my @files = glob("${from}/.??*");
#    printf "@files\n";
#    foreach my $f (@files) {
#        printf "kopiuje $f \n";
#        #system("cp -Rf $f/ $to/");
#        #rcopy("$f/", "$to/") or printf "nie dualo sie $f: $!\n";
#    }
    my $from = File::Spec->catfile("$copy_from");
    $from = quotemeta($from);
    rcopy_glob("${from}/.??*", "$homedir");
#    change_user_group_homedir($uid, "-1", $gid, "-1", "$homedir");
#    return;
}


sub change_user_group_in_homedir {
    my ($new_uid, $old_uid, $new_gid, $old_gid, $homedir) = @_;
    my @errors = ();
    find( sub{
            my ($dev, $ino, $mode, $nlink, $uid, $gid);
            (($dev, $ino, $mode, $nlink, $uid, $gid) = lstat($_)) &&
            (($gid == $old_gid) || ($old_gid == -1)) &&
            (($uid == $old_uid) || ($old_uid == -1)) &&
            (chown $new_uid, $new_gid, $_
            or printf "cound not chown '$_': $!\n")}, $homedir);
}

sub gen_random_pass {
    my $length = shift;
    my $rd = new String::Random;
    my $str = "." x $length;
    return $rd->randpattern("$str");

}

sub encript_pass {
    my $pass = shift;
    my $rd = new String::Random;
    my $str = "s" x 13;
    my $salt = $rd->randpattern("$str");
    print "   $salt\n";
    my $enc = crypt("$pass", "\$6\$$salt");
    return $enc;
}

sub epoch_days {
    return int(time / (60 * 60 * 24));
}


#my $fn = 'shadow';
#{
#    local @ARGV = ($fn);
#    #local $^I = '.bac';
#    while (<>) {
#        s/pawel/inny/g;
#        print;
#    }
#}

sub del_password_record {
    my ($desc, $username) = @_;

    my $Q_username = quotemeta($username);
    $desc->seek(0,0);
    my $out = '';
    my $count = 0;
    while (<$desc>) {
        my $n = s/^${Q_username}:.*$//g;
        if ($n) {
            $count += $n;
        }
        else {
            $out .= $_;
        }
    }
    print $out;

    if ($count == 0) {
        printf "No record removed\n";
        return 0;
    }
    elsif ($count > 1) {
        printf STDERR "Error: $count record removed, should be 1!\n";
        return 0;
    }
    else {
        $desc->seek(0,0);
        print $desc $out;
        truncate($desc, tell($desc));
        return 1;
    }
}

sub add_password_record {
    my ($desc, $username, $password) = @_;

    my $Q_username = quotemeta($username);
    $desc->seek(0,0);
    my $count = 0;
    while (<$desc>) {
        my $n = s/^${Q_username}:.*$//g;
        if ($n) {
            $count += $n;
        }
    }

    if ($count) {
        printf STDERR "Error: record `${username}' already exists\n";
        return 0;
    }

    my $days = epoch_days();
    my $enc_pass = encript_pass($password);
    my $record = "${username}:${enc_pass}:${days}:0:99999:7:::\n";
    print $desc $record;
}

sub change_password_record {
    my ($desc, $username, $new_username, $new_password) = @_;

    if ($new_username eq "") {
        $new_username = $username;
    }

    my $to_point;
    my $enc_new_pass = \$to_point;
    if ($new_password eq "") {
        $enc_new_pass = \$2;
    }
    else {
        $to_point = encript_pass($new_password);
    }

    my $Q_username = quotemeta($username);
    $desc->seek(0,0);
    my $days = epoch_days();
    my $count = 0;
    my $out = '';
    while (<$desc>) {
        my $n = s/^(${Q_username}):([^:]+):([^:]+):(.+):$/${new_username}:$${enc_new_pass}:${days}:$4:/g;
        printf "user-> $1\npass-> $2\ndays-> $3\nrest-> $4\n";
        $out .= $_;
        if ($n) {
            $count += $n;
        }
    }

    if ($count == 0) {
        printf "No record modified\n";
        return 0;
    }
    elsif ($count > 1) {
        printf STDERR "Error: $count record would be modified, should be 1!\n";
        return 0;
    }
    else {
        $desc->seek(0,0);
        print $desc $out;
        truncate($desc, tell($desc));
        return 1;
    }

}

sub set_password_record {
    my ($old_username, )
}
my $sh_desc = new IO::LockedFile("+<shadow");
if (! defined(${sh_desc})) {
    printf "nie udalo sie otworzyc pliku z haslami uzytkownikow \n";
    exit(1);
}

#del_password_record($sh_desc, "p|wel");
#add_password_record($sh_desc, "zbynio","tralalala");
#add_password_record($sh_desc, "ter","stare");
#change_password_record($sh_desc, "ter", "zeresa", "nowe");
undef($sh_desc);
#my $o = '';
#while (<$sh_desc>) {
#    s/(p)(a)(wel)/$1\|$3/g;
#    $o .= $_;
#}
#
#$sh_desc->seek(0,0);
#print $sh_desc $o;
#truncate($sh_desc, tell($sh_desc));

#print "\n";
#$sh_desc->seek(0,0);
#print <$sh_desc>;

undef($sh_desc);

#print epoch_days;
# Create a complex structure
my %hash = (
    'user1' => {
        'uid'   => '1000',
        'pass'  => 'asdas',
        'modification'  => 'asda',
    },
    'user2' => {
        'uid'   => '1001',
        'pass'  => 'kra',
    },
);
# See what it looks like
print "Here is the structure before dumping to file:\n";
dump \%hash;

# Print structure to file
open my $out, '>', 'dump_struct' or die $!;
print {$out} dump \%hash;
close $out;

# Read structure back in again
open my $in, '<', 'dump_struct' or die $!;
my $data;
{
    local $/;    # slurp mode
    $data = eval <$in>;
}
close $in;
# See what the structure read in looks like
print "Here is the structure after reading from file:\n";
dump $data;
my %hh = %{$data};
dump \%hh;
my $saf = new Safe;
#$data = eval  'die'; warn $@ if $@;
undef($data);# =  eval('');

if (!(defined($data)) || !(ref($data) eq "HASH")) {
print "ADASSD\n";
#%hh = %{$data}; warn $@ if $@;
#printf "data->\n";
#dump \%hh;
}
else
{
printf "niezid\n";
}
#exit 0;
#my $p = gen_random_pass(11);
#printf "$p\n";
#my $e = encript_pass($p);
#printf "$e";

my %log = (
    'zbych' => {'uid' => 1001, 'pass'=>'asd' },
    'alek' => {'uid' => 1002, 'pass'=>'sra' },
);

dump \%log;

$log{'marek'} = {'uid' => 1003, 'pass' => 'inne'};

$log{'zbych'} = {'uid' => 2003, 'pass' => 'iasda', 'pole'=>'puste'};
dump \%log;

delete($log{'marek'});

dump \%log;


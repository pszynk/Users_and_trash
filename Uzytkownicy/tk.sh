#!/usr/bin/perl
use Tk;
use strict;

my $global_home_directory;
my $global_start_group;
my $global_shell;
my $global_login;
my $global_UID;
my $logger="/var/log/tk_users.log";

my $mw = new MainWindow;
fill_window($mw, 'Main');

# create menu
my $menu = $mw -> Frame(-relief=> 'groove', -borderwidth=>3, -background=>'white') ->pack(-side=>'top',-fill=>'x');
my $file_button = $menu-> Menubutton(-text=>'File', -background=>'white',-foreground=>'black') -> pack(-side=>'left');
my $user_button = $menu-> Menubutton(-text=>'User', -background=>'white',-foreground=>'black') -> pack(-side=>'left');
my $group_button = $menu-> Menubutton(-text=>'Group', -background=>'white',-foreground=>'black') -> pack(-side=>'left');

# create options in menu
$user_button -> command(-label=>'Add User', -command=>\&add_user);
$user_button -> command(-label=>'Change User', -command=>\&modify_user);
$user_button -> command(-label=>'Remove User', -command=>\&remove_user);
$group_button -> command(-label=>'View User Group', -command=>\&modify_group);
$group_button -> command(-label=>'View Groups', -command=>\&view_gruop_users);
$file_button -> command(-label=>'Exit', -command=>sub { exit } );

# user list
my $frame = $mw -> Frame(-background=>"blue") -> pack();
my $list = $frame -> Scrolled('Listbox', -scrollbars=> 'osoe', -setgrid=> 'yes', -width=>40, -height=>20) -> pack();
$list -> grid(-row=>2, -column=>1);

sub load_users{
$list->delete(0,'end');
open(OUT, "<", "/etc/passwd");	
while(<OUT>)
{
	my @line_data = split(/:/, $_);
	if ( $line_data[2] > 1000 && $line_data[2] < 65534){
	$list->insert('end',$line_data[0]);}
}
close OUT;
}

load_users();

sub check_available_uid{
	my($my_UID) = @_;
	my $available;
		
	open(OUT, "<", "/etc/passwd");
		
	while(<OUT>)
	{
		my @line_data = split(/:/, $_);
		if($line_data[2] == $my_UID)
		{
			return $available = "false";
		}
	}
	close OUT;
	return $available = "true";
}

sub check_available_login{
	my($my_UID) = @_;
	my $available;
		
	open(OUT, "<", "/etc/passwd");
		
	while(<OUT>)
	{
		my @line_data = split(/:/, $_);
		if($line_data[0] eq $my_UID)
		{
			return $available = "false";
		}
	}
	close OUT;
	return $available = "true";
}

sub get_available_uid{
	my $last_UID_value = 1000;	
	open(OUT, "<", "/etc/passwd");
		
	while(<OUT>)
	{
		my @line_data = split(/:/, $_);
		my $val = $line_data[2];
		if($val >= 1000 && $val <= 6000 &&
			$val>=$last_UID_value)
		{
			$last_UID_value = $line_data[2];
		}
	}
	close OUT;
	return $last_UID_value;
}

sub fill_window {
	my ($window, $header) = @_;
        $window->Label(-text => $header)->pack;
        $window->Button(
            -text    => 'close',
            -command => [$window => 'destroy']
	)->pack(-side => 'bottom');
}

sub load_user_data{
	my($user_login) = @_;
	open(OUT, "<", "/etc/passwd");
	while(<OUT>)
	{
		my @line_data = split(/:/, $_);
		if ( $line_data[0] eq $user_login){
		return @line_data;
		}
	}
	return "";
}

sub add_user {
	my $mwlocal = MainWindow->new();
	$mwlocal->Label(-text =>"Add User");
	my $label_login = $mwlocal-> Label(-text=>"Login");
	my $entry_login = $mwlocal-> Entry();

	my $label_uid = $mwlocal-> Label(-text=>"UID");
	my $entry_uid = $mwlocal-> Entry();

	$global_UID = get_available_uid()+1;
	$entry_uid -> insert(0,$global_UID);

	my $label_home = $mwlocal-> Label(-text=>"Home dir");
	my $entry_home = $mwlocal-> Entry();
	my $label_powloka = $mwlocal-> Label(-text=>"Shell");
	my $entry_powloka = $mwlocal-> Entry();
	my $label_group = $mwlocal-> Label(-text=>"Group");
	my $entry_group = $mwlocal-> Entry();

	my $label_warning = $mwlocal-> Label(-text=>"Warnings:");
	my $entry_warning = $mwlocal-> Entry();

	$global_login = $entry_login->get();
	$global_shell = "/bin/sh";

	my $send_button = $mwlocal -> Button(-text=>"Create",-command=> sub {
		
		if ( $entry_login->get() eq "" ){
			$entry_warning->delete(0,999);
			$entry_warning->insert(0,"Nie podano loginu!");
			return;
		}

		my $myVar1=check_available_login($entry_login->get());
		if ( $myVar1 ne "true" ){
			$entry_warning->delete(0,999);
			$entry_warning->insert(0,"Podany login jest zajety");
			return;
		}

		my $Tuid=$entry_uid->get();
		if ( $Tuid eq "" || $Tuid == /^\d+$/ ){
			$entry_warning->delete(0,999);
			$entry_warning->insert(0,"Nie podano UID!");
			return;
		}

		my $myVar2=check_available_uid($Tuid);
		if ( $myVar2 ne "true" ){
			$entry_warning->delete(0,999);
			$entry_warning->insert(0,"Podany UID istnieje");
			return;
		}
		
		$entry_warning->delete(0,999);
		
		my $genPW=`pwgen -1`;
		my $pass=crypt("$genPW","salt");

		$global_home_directory = "/home/$global_login";
		$global_UID = $entry_uid->get();
		$global_login = $entry_login->get();
		$global_shell = "/bin/sh";

		`useradd -u $global_UID -s $global_shell -m -p $pass $global_login`;

		save_user_to_root_file("$global_login","$global_UID","$genPW");

		print "password is $genPW";
		load_users();
		} ) -> pack();

	my $cancle_button = $mwlocal-> Button(
		-text=>'Cancel',
		-command=> sub	{ $mwlocal -> destroy; }
		) -> pack();
	
	$label_login -> grid(-row=>2, -column=>1);
	$entry_login -> grid(-row=>2, -column=>2);
	$label_uid -> grid(-row=>3, -column=>1);
	$entry_uid -> grid(-row=>3, -column=>2);
	$label_home -> grid(-row=>5, -column=>1);
	$entry_home -> grid(-row=>5, -column=>2);
	$label_group -> grid(-row=>6, -column=>1);
	$entry_group -> grid(-row=>6, -column=>2);
	$label_powloka -> grid(-row=>7, -column=>1);
	$entry_powloka -> grid(-row=>7, -column=>2);
	$label_warning -> grid(-row=>8, -column=>1);
	$entry_warning -> grid(-row=>8, -column=>2);
	
	$send_button -> grid(-row=>9, -column=>1);
	$cancle_button -> grid(-row=>9, -column=>2);

	MainLoop;
}

sub remove_user {
	my $sel=$list->curselection();

	if ($sel eq ""){
		my $ftp_warn = $mw->messageBox(
  		-title   => 'NOT RLY',
  		-message => "Select user first!",
  		-type    => 'ok',
  		-icon    => 'error',
		);
		return;
	}

	my $ftp_warn = $mw->messageBox(
  		-title   => 'SERIOUSLY?',
  		-message => "Are you sure?",
  		-type    => 'YesNo',
  		-icon    => 'question',
	);
	if ( $ftp_warn eq 'No' ) {
  		return;
	}
	
	my $value=$list->get($sel);
	`deluser $value --remove-home`;
	rem($list->get($sel));
	load_users();
}


sub modify_user {
	
	my $sel=$list->curselection();

	if ($sel eq ""){
		my $ftp_warn = $mw->messageBox(
  		-title   => 'NOT RLY',
  		-message => "Select user first!",
  		-type    => 'ok',
  		-icon    => 'error',
		);
		return;
	}
	my $value=$list->get($sel);
	my @data=load_user_data($value);

my $mwlocal = MainWindow->new();
	$mwlocal->Label(-text =>"Modify User");
	my $label_login = $mwlocal-> Label(-text=>"Login");
	my $entry_login = $mwlocal-> Entry();
	$entry_login->insert(0,$data[0]);

	my $label_uid = $mwlocal-> Label(-text=>"UID");
	my $entry_uid = $mwlocal-> Entry();
	$entry_uid -> insert(0,$data[2]);

	my $label_home = $mwlocal-> Label(-text=>"Home dir");
	my $entry_home = $mwlocal-> Entry();
	$entry_home->insert(0,$data[5]);

	my $label_powloka = $mwlocal-> Label(-text=>"Shell");
	my $entry_powloka = $mwlocal-> Entry();
	$entry_powloka->insert(0,$data[6]);

	my $label_group = $mwlocal-> Label(-text=>"Group");
	my $entry_group = $mwlocal-> Entry();
	$entry_group  -> insert(0,$data[3]);

	my $label_warning = $mwlocal-> Label(-text=>"Warnings:");
	my $entry_warning = $mwlocal-> Entry();

	my $send_button = $mwlocal -> Button(-text=>"Modify",-command=> sub {
		$value=$list->get($sel);
		@data=load_user_data($value);

		if ( $entry_login->get() eq "" ){
			$entry_warning->delete(0,999);
			$entry_warning->insert(0,"Nie podano loginu!");
			return;
		}

		my $myVar1=check_available_login($entry_login->get());

		my $aaa=$entry_login->get();
		print "#### LOGIN = $aaa #### DATA = $data[0] ###\n";
		if ($entry_login->get() ne $data[0] ){
		if ( $myVar1 ne "true" ){
			$entry_warning->delete(0,999);
			$entry_warning->insert(0,"Podany login jest zajety");
			return;
		}
		}

		my $Tuid=$entry_uid->get();
		if($Tuid ne $data[2]){
		if ( $Tuid eq "" || $Tuid == /^\d+$/ ){
			$entry_warning->delete(0,999);
			$entry_warning->insert(0,"Nie podano UID!");
			return;
		}

		my $myVar2=check_available_uid($Tuid);
		if ( $myVar2 ne "true" ){
			$entry_warning->delete(0,999);
			$entry_warning->insert(0,"Podany UID istnieje");
			return;
		}

		}

		my $gidT=$entry_group->get();
		if ( $gidT < 1000 || $gidT >= 65534 ){
			$entry_warning->delete(0,999);
			$entry_warning->insert(0,"GID musi byc > 1000 !");
			return;
		}
		
		$entry_warning->delete(0,999);

		print "\n\nMODIFY DONE\n\n";
		#modify
		my $oldLogin=$data[0];
		my $oldUID=$data[2];
		my $login=$entry_login->get();
		my $uid=$entry_uid->get();
		my $gid=$entry_group->get();
		my $hdir=$entry_home->get();
		my $shell=$entry_powloka->get();
		$shell =~ s/^\s+//; #remove leading spaces
		$shell =~ s/\s+$//; #remove trailing spaces
		`usermod -d $hdir -s $shell --uid $uid --login $login -m $oldLogin`;

		update($oldUID,$login,$uid);

		load_users();
		} ) -> pack();

	my $cancle_button = $mwlocal-> Button(
		-text=>'Cancel',
		-command=> sub	{ $mwlocal -> destroy; }
		) -> pack();
	
	$label_login -> grid(-row=>2, -column=>1);
	$entry_login -> grid(-row=>2, -column=>2);
	$label_uid -> grid(-row=>3, -column=>1);
	$entry_uid -> grid(-row=>3, -column=>2);
	$label_home -> grid(-row=>5, -column=>1);
	$entry_home -> grid(-row=>5, -column=>2);
	$label_group -> grid(-row=>6, -column=>1);
	$entry_group -> grid(-row=>6, -column=>2);
	$label_powloka -> grid(-row=>7, -column=>1);
	$entry_powloka -> grid(-row=>7, -column=>2);
	$label_warning -> grid(-row=>8, -column=>1);
	$entry_warning -> grid(-row=>8, -column=>2);
	
	$send_button -> grid(-row=>9, -column=>1);
	$cancle_button -> grid(-row=>9, -column=>2);

	MainLoop;

}


sub save_user_to_root_file {
	my($user,$uid,$pass) = @_;

	my $ch=0;
	if ( ! -e $logger ){
		$ch=1;
	}
	open(LOG,">>",$logger);

	if ( $ch == 1 ){
		`chmod 700 $logger`;
	}

	print LOG "$user:$uid:$pass\n";
	close LOG;
	
}

sub update{ 
    my($old_uid,$user,$uid) = @_; 
    
    local @ARGV = ($logger); 
    local $^I = '.bac'; 
        
    while(<>){ 
        chomp; 
        my @line = split(/:/,$_); 
        my $uid_prev = $line[1]; 
        my $user_prev = $line[0]; 

        if($old_uid eq $uid_prev){
            s/:$uid_prev:/:$uid:/; 
	    s/$user_prev:/$user:/;

            print $_ ."\n"; 
        }else{ 
            print $_ ."\n"; 
        } 
    } 
}

sub rem{ 
    my($user) = @_; 
    
    local @ARGV = ($logger); 
    local $^I = '.bac'; 
        
    while(<>){ 
        chomp; 
        my @line = split(/:/,$_); 
        my $uid = $line[1]; 
        my $muser = $line[0]; 
	my $pass = $line[2];

        if($user == $muser){
            s/$muser:$uid:$pass//;
            print $_ .""; 
        }else{ 
            print $_ ."\n"; 
        } 
    } 
}

sub view_gruop_users {

	my $mwlocal = MainWindow->new();
	$mwlocal->Label(-text =>"Group Users");
	my $label_uid = $mwlocal-> Label(-text=>"Grupy       i      Userzy");
	my $entry_uid = $mwlocal-> Entry();

	$label_uid -> grid(-row=>1, -column=>1);
	$entry_uid -> grid(-row=>1, -column=>2);

# gid list
my $list3 = $mwlocal -> Scrolled('Listbox', -scrollbars=> 'osoe', -setgrid=> 'yes', -width=>20, -height=>10) -> pack();
$list3 -> grid(-row=>2, -column=>1);

#user list
my $list4 = $mwlocal -> Scrolled('Listbox', -scrollbars=> 'osoe', -setgrid=> 'yes', -width=>20, -height=>10) -> pack();
$list4 -> grid(-row=>2, -column=>2);

	load_groups($list3);
	my $show = $mwlocal-> Button(
		-text=>'Show Users',
		-command=> sub	{ 

		
	my $sel=$list3->curselection();

	if ($sel eq ""){
		my $ftp_warn = $mw->messageBox(
  		-title   => 'NOT RLY',
  		-message => "Select group first!",
  		-type    => 'ok',
  		-icon    => 'error',
		);
		return;
	}
	my $value=$list3->get($sel);

	$list4->delete(0,'end');
	group_users("$value",$list4);

		}
		) -> pack();
	$show->grid(-row=>3, -column=>2);


	my $rem_button = $mwlocal-> Button(
		-text=>'Remove users with GID',
		-command=> sub	{ 

		my $ftp_warn = $mw->messageBox(
	  		-title   => 'SERIOUSLY?',
	  		-message => "Are you sure?",
	  		-type    => 'YesNo',
	  		-icon    => 'question',
		);
		if ( $ftp_warn eq 'No' ) {
	  		return;
		}

		
		foreach ( $list4->get(0,'end') ){
			print "removing user $_ ...\n";
			#UNCOMMENT
			#`deluser $_ --remove-home`;
			#rem($_);
		}
	
		}
		) -> pack();
	$rem_button->grid(-row=>4, -column=>2);


	my $cancle_button = $mwlocal-> Button(
		-text=>'Cancel',
		-command=> sub	{ $mwlocal -> destroy; }
		) -> pack();
	$cancle_button->grid(-row=>5, -column=>2);

	MainLoop;

}

sub load_groups{
	my($list) = @_;

	open(OUT, "<", "/etc/group");
		
	while(<OUT>)
	{
		my @line_data = split(/:/, $_);
		if($line_data[2] > 1000 && $line_data[2] < 65534)
		{
			$list->insert('end',$line_data[2]);
		}
	}
	close OUT;
}

sub modify_group {

	my $sel=$list->curselection();

	if ($sel eq ""){
		my $ftp_warn = $mw->messageBox(
  		-title   => 'NOT RLY',
  		-message => "Select user first!",
  		-type    => 'ok',
  		-icon    => 'error',
		);
		return;
	}

	my $value=$list->get($sel);
	my @data=load_user_data($value);

	my $gid_show=$data[3];

	print "@data\n\n";

	my $mwlocal = MainWindow->new();
	$mwlocal->Label(-text =>"Add User");
	my $label_uid = $mwlocal-> Label(-text=>"Userzy dla GID = $gid_show");
	my $entry_uid = $mwlocal-> Entry();

	#my $add_button

	$label_uid -> grid(-row=>1, -column=>1);
	$entry_uid -> grid(-row=>1, -column=>2);

# gid list
my $list2 = $mwlocal -> Scrolled('Listbox', -scrollbars=> 'osoe', -setgrid=> 'yes', -width=>20, -height=>10) -> pack();
$list2 -> grid(-row=>2, -column=>2);

	my $rem_button = $mwlocal-> Button(
		-text=>'Remove users with GID',
		-command=> sub	{ 

		my $ftp_warn = $mw->messageBox(
	  		-title   => 'SERIOUSLY?',
	  		-message => "Are you sure?",
	  		-type    => 'YesNo',
	  		-icon    => 'question',
		);
		if ( $ftp_warn eq 'No' ) {
	  		return;
		}

		

		foreach ( $list2->get(0,'end') ){
			my $value=$list->get($sel);
			print "removing user $_ ...\n";
			#UNCOMMENT
			#`deluser $_ --remove-home`;
			#rem($_);
		}
	
		}
		) -> pack();
	$rem_button->grid(-row=>3, -column=>2);

	my $add_button = $mwlocal-> Button(
		-text=>'Add user to group',
		-command=> sub	{

		my $myUID=$entry_uid->get();
		if ($myUID eq ""){
			my $ftp_warn = $mw->messageBox(
	  		-title   => 'NOT RLY',
	  		-message => "UID is empty!",
	  		-type    => 'ok',
	  		-icon    => 'error',
			);
			return;
		}

		if ($myUID < 1000 || $myUID > 65533){
			my $ftp_warn = $mw->messageBox(
	  		-title   => 'NOT RLY',
	  		-message => "Cant use that UID!",
	  		-type    => 'ok',
	  		-icon    => 'error',
			);
			return;
		}



		
		`usermod -G $myUID $data[0]`;

	}
		) -> pack();
	$add_button->grid(-row=>4, -column=>2);

	my $cancle_button = $mwlocal-> Button(
		-text=>'Cancel',
		-command=> sub	{ $mwlocal -> destroy; }
		) -> pack();
	$cancle_button->grid(-row=>5, -column=>2);
	
	group_users("$gid_show",$list2);
	MainLoop;

}

sub group_users{
	my($gid,$list) = @_;

	open(OUT, "<", "/etc/group");
		
	while(<OUT>)
	{
		my @line_data = split(/:/, $_);
		if($line_data[2] eq $gid)
		{
			my $count = 0;
			my @groups = split(/,/, $line_data[3]);
			for ( $count ; $count <= @groups - 1 ; $count++){
				chomp($groups[$count]);
				if("$groups[$count]" eq ""){
					next;
				}
				$list->insert('end',$groups[$count]);
			}
			$list->insert('end',$line_data[0]);
			last;
		}
	}
	close OUT;
}


sub finito {
	exit;
}


MainLoop;

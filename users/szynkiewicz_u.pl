#!/usr/bin/perl

use strict;
use warnings;

use Fcntl qw(:flock);
use Tk;
use Tk::NoteBook;
use Tk::MListbox;
use Unix::PasswdFile;
use Unix::GroupFile;
use IO::LockedFile;
use Set::Scalar;
use Data::Dump qw(dump ddx);
use File::Path qw(make_path);
use File::Find;
use File::Spec;
use File::Copy::Recursive qw(rcopy dircopy rcopy_glob rmove);
use String::Random;
use Safe;
use Time::Piece;
use Time::Seconds;

# indeksy zaznaczonych uzytkownika, grupy
my $user_selc=new Set::Scalar->new();
my $group_selc=new Set::Scalar->new();

my $ml_mode="none";

my $default_copy_dir="/etc/skel/";
my $copy_dir=$default_copy_dir;
# hashe wszsystkich sledoznych uzytkownikow i grup
my %users_name_uid = ();    # nazwa => uid
my %groups_name_gid = ();   # nazwa => gid

# sety dla obu list wyboru
my $in_list_set = new Set::Scalar();
my $out_list_set = new Set::Scalar();

# sciezki do plikow danych (w formacie Unixowym)
my $folder_path = '/etc';
my $passwdFile_path = "${folder_path}/passwd";
#my $passwdFile_path = "passwd1";
my $shadowFile_path = "${folder_path}/shadow";
#my $shadowFile_path = "shadow";
my $groupFile_path = "${folder_path}/group";
#my $groupFile_path = "group";
my $gshadowFile_path = "${folder_path}/gshadow";
my @all_file_paths = (${passwdFile_path}, ${shadowFile_path}, ${groupFile_path}); # ${gshadowFile_path});

#logi
my $log_path = '.users.log';
my %log_data = ();

# wskazniki na obiekty klasy Unix;
my $pw_file;
my $grp_file;

# wskazniki na klase LockedFile plikow shadow i gshadow
my $sh_desc;
my $gsh_desc;


$SIG{'INT'} = 'CLEANUP';
### ERROR HANDLING ########################################################
sub print_err_str {
    my $err = shift;
    my @lines = split /\n/, $err;
    printf("\n");
    foreach my $line (@lines) {
        printf(STDERR "Error users: %s\n", ${line});
    }
}

sub print_err_msg {
    printf(STDERR "\nError users: ");
    printf(STDERR @_);
}


### DATA FILES HANDLING ###################################################

sub create_folder {
    my $err = qx(mkdir -p ${folder_path} 2>&1);
    if ($? != 0) {
        print_err_str($err);
        print_err_msg("nie udalo sie utworzyc folderu ${folder_path}\n");
        exit(1);
    }
    create_files(@all_file_paths);
    $err = qx(chown root:root ${folder_path} 2>&1);
    if ($? != 0) {
        print_err_str($err);
        print_err_msg("nie udalo sie zmienic wlasciciela folderowi ${folder_path}\n");
        exit(1);
    }
#    $err = qx(chomod  755 ${folder_path} 2>&1);
#    if ($? != 0) {
#        print_err_str($err);
#        print_err_msg("nie udalo sie zmienic praw folderowi ${folder_path}\n");
#        exit(1);
#    }
#
}

sub create_files {
    my @files = @_; #(${passwdFile_path}, ${shadowFile_path}, ${groupFile_path}, ${gshadowFile_path});
    if ( scalar(@files) == 0 ) {
        return 0;
    }
    my $err = qx(touch @{files} 2>&1);
    if ($? != 0) {
        print_err_str($err);
        print_err_msg("nie udalo utworzyc plikow @{files}\n");
        exit(1);
    }

    $err = qx(chown root:root @{files} 2>&1);
    if ($? != 0) {
        print_err_str($err);
        print_err_msg("nie udalo zmienic wlasciciela @{files}\n");
        exit(1);
    }

    $err = qx(chmod 644 @{files} 2>&1);
    if ($? != 0) {
        print_err_str($err);
        print_err_msg("nie udalo zmienic praw @{files}\n");
        exit(1);
    }
}


sub prepare_files {

    if (-e ${folder_path}) {
        my @missing_files = map { ! -e ${_} ? ${_} : ()} @all_file_paths;
        create_files(@missing_files);
    }
    else {
        create_folder();
    }

    return;
}

sub open_data_files {
    $pw_file = new Unix::PasswdFile($passwdFile_path);
    if (! defined(${pw_file})) {
        print_err_msg("nie udalo sie otworzyc pliku z uzytkownikami ${passwdFile_path}");
        exit(1);
    }

    $grp_file = new Unix::GroupFile($groupFile_path);
    if (! defined(${grp_file})) {
        print_err_msg("nie udalo sie otworzyc pliku z uzytkownikami ${groupFile_path}");
        exit(1);
    }

    $sh_desc = new IO::LockedFile("+<${shadowFile_path}");
    if (! defined(${sh_desc})) {
        print_err_msg("nie udalo sie otworzyc pliku z haslami uzytkownikow ${shadowFile_path}");
        exit(1);
    }
    return;
    $gsh_desc = new IO::LockedFile("+<${gshadowFile_path}");
    if (! defined(${gsh_desc})) {
        print_err_msg("nie udalo sie otworzyc pliku z haslami grup ${gshadowFile_path}");
        exit(1);
    }
}

sub close_data_files {
    undef(${pw_file});
    undef(${grp_file});
    undef(${sh_desc});
    undef(${gsh_desc});
}

sub load_log {
    open my $log, '<', $log_path or
        ( print_err_msg("nie udalo sie wczytac logu `$log_path': $!") and (return 0));

    my $data;
    my $safe = new Safe;
    {
        local $/;
        $data = $safe->reval(<$log>);
    }
    close $log;

    if ((! defined($data)) || !(ref($data) eq "HASH")) {
        print_err_msg("nie udalo zinterpretowac logu `$log_path': $!");
        return 0;
    }
    %log_data = %{$data};
}

sub save_log {
    open my $log, '>', $log_path or
        ( print_err_msg("nie udalo sie zapisac logu `$log_path': $!") and (return 0));

#    if (! defined(%log_data)) {
#        print_err_msg("nie udalo sie zapisac logu `$log_path': $!");
#        return 0;
#    }
#
    print {$log} dump \%log_data;
    close $log;
    chown "root", "root", $log_path;
    chmod 0600, $log_path;
}
sub write_user_to_log {
    my ($username, $uid, $pass) = @_;
    my $t = localtime;
    my $date = $t->datetime;
    $log_data{$username} = {'uid' => "$uid", "password" => "$pass", "timestamp" => "$date"};
    return 1;
}
sub delete_user_from_log {
    my $username = shift;
    if (defined($log_data{$username})) {
        delete($log_data{$username});
        return 1;
    }
    return 0;
}

sub load_users {
    if (! defined($pw_file)) {
        printf "nieudalo sie\n";
        return -1;
    }

    %users_name_uid = ();
    foreach my $username ($pw_file->users('name')) {
        my $uid = $pw_file->uid($username);
#        printf "\n$username - $uid\n";
        $users_name_uid{$username}=$uid;
    }

#    foreach my $key (keys(%users_name_uid)) {
#        printf("user-> %s uid -> %d\n", $key, $users_name_uid{$key});
#    }

    $pw_file->commit();
}


sub load_groups {
    if (! defined($grp_file)) {
        printf "nieudalo sie\n";
        return -1;
    }

    %groups_name_gid = ();
    foreach my $groupname ($grp_file->groups('name')) {
        $groups_name_gid{$groupname}=$grp_file->gid($groupname);
    }

    foreach my $key (keys(%groups_name_gid)) {
#        printf("group-> %s gid -> %d\n", $key, $groups_name_gid{$key});
    }

    $grp_file->commit();
}

#--------- GUI -------------

#>>> funckje pomicnicze
sub fill_window {
    my ($window, $header) = @_;
        $window->Label(-text => $header)->pack;
        $window->Button(
            -text    => 'close',
            -command => [$window => 'destroy']
    )->pack(-side => 'bottom');
}

######### VIEW ############################################################################################################
my $mw = new MainWindow;
$mw->geometry( "710x650" );
$mw->resizable(0, 0);
fill_window($mw, 'Main');

#--- MENU ------------------------------------
my $menu = $mw -> Frame(-relief=> 'groove', -borderwidth=>3, -background=>'white') ->pack(-side=>'top',-fill=>'x');
my $file_mbutton = $menu-> Menubutton(-text=>'File', -background=>'white',-foreground=>'black') -> pack(-side=>'left');
my $user_mbutton = $menu-> Menubutton(-text=>'User', -background=>'white',-foreground=>'black') -> pack(-side=>'left');
my $group_mbutton = $menu-> Menubutton(-text=>'Group', -background=>'white',-foreground=>'black') -> pack(-side=>'left');

# create options in menu
$user_mbutton -> command(-label=>'Add User', -command=>\&setup_user_add);
#$user_mbutton -> command(-label=>'Change User', -command=>\&modify_user);
$user_mbutton -> command(-label=>'Copy direcotry', -command=>\&set_copy_directory);
$user_mbutton -> command(-label=>'Remove User', -command=>\&try_remove_user);

sub set_copy_directory {
    my $lw = MainWindow->new();
    fill_window($lw, 'Set copy directory');
    my $lentry = $lw->Entry()->pack();
    $lentry->insert(0, $copy_dir);
    my $lok = $lw->Button(-text=>'ok', -command=>sub {$copy_dir = $lentry->get();})->pack();
}


$group_mbutton -> command(-label=>'Add Group', -command=>\&setup_group_add);
$group_mbutton -> command(-label=>'Remove Group', -command=>\&try_remove_group);
#$group_mbutton -> command(-label=>'View User Group', -command=>\&modify_group);
#$group_mbutton -> command(-label=>'View Groups', -command=>\&view_gruop_users);

$file_mbutton -> command(-label=>'Exit', -command=>sub { exit } );#


#--- MAIN FRAMES --------------------------------
my $tabs_frame = $mw->Frame(-background=>'cyan')->pack(-side=>'left', -fill=>'y',-anchor=>'nw', -expand=>0, -ipadx=>"27");
my $util_frame = $mw->Frame(-background=>'cyan')->pack(-side=>'right', -fill=>'both', -expand=>1);

#--- TABS (tabs_frame)
my $tabs = $tabs_frame->NoteBook()->pack( -fill=>'both', -expand=>1 );

# users >>>
my $users_tab = $tabs->add("users", -label=>"Users", -raisecmd=>\&setup_clear);
#my $users_list = $users_tab->Scrolled('Listbox', -scrollbars=>'osoe', -setgrid=>'yes', -selectmode=>'single', -exportselection=>0)->pack(-fill=>'both', -expand=>1);
my $users_list = $users_tab->Scrolled('MListbox', -columns=>[[-text=>'User'], [-text=>'UID']],
    -scrollbars=>'osoe',  -selectmode=>'multiple')->pack(-fill=>'both', -expand=>1);


$users_list->bindRows('<Button-1>'=>\&select_user);
# <<< users


# grups >>>
my $groups_tab = $tabs->add( "groups", -label=>'Groups',-raisecmd=>\&setup_clear); 
my $groups_list = $groups_tab->Scrolled('MListbox', -columns=>[[-text=>'Group'], [-text=>'GID']],
    -scrollbars=>'osoe',  -selectmode=>'multiple')->pack(-fill=>'both', -expand=>1);
#my $groups_list = $groups_tab->Scrolled('Listbox', -scrollbars=>'osoe', -setgrid=>'yes', -selectmode=>'single', -exportselection=>0)->pack(-fill=>'both', -expand=>1);
$groups_list->bindRows('<Button-1>'=>\&select_group);
# <<< grups


#--- FORMS (form_frame)
my $form_frame = $util_frame->Frame(-background=>'red');

######## USER FORM ##################################################################################################
my $user_form = $form_frame->Frame(-background=>'blue');

# nazwa - pole
my $u_label_login = $user_form->Label(-text=>"Login");
#my $u_entry_login = $user_form-> Entry();
my $u_entry_login = $user_form->Scrolled('Entry', -scrollbars=>'os');

my $u_label_uid = $user_form-> Label(-text=>"UID");
my $u_entry_uid = $user_form-> Scrolled('Entry', -scrollbars=>'os');

my $u_label_pass = $user_form->Label(-text=>"Password");
my $u_entry_pass = $user_form->Entry();
my $u_label_rpass = $user_form->Label(-text=>"Repeat password");
my $u_entry_rpass = $user_form->Entry();

my $u_label_home = $user_form-> Label(-text=>"Home dir");
my $u_entry_home = $user_form-> Entry();

my $u_label_shell = $user_form-> Label(-text=>"Shell");
my $u_entry_shell = $user_form-> Entry();

my $u_label_group = $user_form-> Label(-text=>"Group");
my $u_entry_group = $user_form-> Entry();

my $u_create_user_button = $user_form->Button(-text=>'Create', -command=>[\&test_sub, 'arg1', 'arg2']);
my $u_cancel_button = $user_form->Button(-text=>'Cancel', -command=>\&setup_clear); 

$u_label_login -> grid(-row=>0, -column=>0);
$u_entry_login -> grid(-row=>0, -column=>2);
$u_label_uid -> grid(-row=>1, -column=>0);
$u_entry_uid -> grid(-row=>1, -column=>2);
$u_label_pass->grid(-row=>2, -column=>0);
$u_entry_pass->grid(-row=>2, -column=>2);
$u_label_rpass->grid(-row=>3, -column=>0);
$u_entry_rpass->grid(-row=>3, -column=>2);
$u_label_home -> grid(-row=>4, -column=>0);
$u_entry_home -> grid(-row=>4, -column=>2);
$u_label_group -> grid(-row=>5, -column=>0);
$u_entry_group -> grid(-row=>5, -column=>2);
$u_label_shell -> grid(-row=>6, -column=>0);
$u_entry_shell -> grid(-row=>6, -column=>2);

$u_create_user_button -> grid(-row=>7, -column=>0);
$u_cancel_button -> grid(-row=>7, -column=>2);


######## GRUP FORM ##################################################################################################
my $group_form = $form_frame->Frame(-background=>'green');

# nazwa - pole
my $g_label_name = $group_form-> Label(-text=>"Name");
#my $g_entry_name = $group_form-> Entry();
my $g_entry_name = $group_form->Scrolled('Entry', -scrollbars=>'os');

my $g_label_gid = $group_form-> Label(-text=>"GID");
my $g_entry_gid = $group_form-> Scrolled('Entry', -scrollbars=>'os');

$g_label_name -> grid(-row=>2, -column=>1);
$g_entry_name -> grid(-row=>2, -column=>2);
$g_label_gid -> grid(-row=>3, -column=>1);
$g_entry_gid -> grid(-row=>3, -column=>2);

my $g_create_group_button = $group_form->Button(-text=>'Create');
my $g_cancel_button = $group_form->Button(-text=>'Cancel', -command=>\&setup_clear);

$g_cancel_button-> grid(-row=>5, -column=>1);
$g_create_group_button-> grid(-row=>5, -column=>2);


######## LISTS FRAME ##################################################################################################
my $movelist_frame = $util_frame->Frame(-background=>'yellow');


# radiobuttons
my $ml_none_radiobutton = $movelist_frame->Radiobutton(-text=>"None", -value=>"none", -variable=>\$ml_mode, -command=>\&lock_movable_list_rest);
my $ml_change_radiobutton = $movelist_frame->Radiobutton(-text=>"Change", -value=>"change", -variable=>\$ml_mode, -command=>\&unlock_movable_list_rest);
my $ml_add_radiobutton = $movelist_frame->Radiobutton(-text=>"Add", -value=>"add", -variable=>\$ml_mode, -command=>\&unlock_movable_list_rest);

# labels
my $ml_in_label = $movelist_frame->Label(-text=>'in list');
my $ml_out_label = $movelist_frame->Label(-text=>'out list');

# listboksy
my $ml_in_list = $movelist_frame->Scrolled('Listbox', -scrollbars=>'osoe',-selectmode=>'multiple');
my $ml_out_list = $movelist_frame->Scrolled('Listbox', -scrollbars=>'osoe',-selectmode=>'multiple');

#przyciski przesylania
my $ml_in2out_button = $movelist_frame->Button(-text=>'  v  ', -command=>[\&move_selection, $ml_in_list, $ml_out_list, 0]); 
my $ml_out2in_button = $movelist_frame->Button(-text=>'  ^  ', -command=>[\&move_selection, $ml_out_list, $ml_in_list, 1]);

#przyciski zaznaczenia
my $ml_in_all_button = $movelist_frame->Button(-text=>'all', -command=>sub{$ml_in_list->selectionSet(0, 'end')}); #TODO -command i strzalki zamias v^
my $ml_in_none_button = $movelist_frame->Button(-text=>'none', -command=>sub{$ml_in_list->selectionClear(0, 'end')}); #TODO -command i strzalki zamias v^
my $ml_out_all_button = $movelist_frame->Button(-text=>'all', -command=>sub{$ml_out_list->selectionSet(0, 'end')}); #TODO -command
my $ml_out_none_button = $movelist_frame->Button(-text=>'none', -command=>sub{$ml_out_list->selectionClear(0, 'end')}); #TODO -command

$ml_none_radiobutton->grid(-row=>0, -column=>0);
$ml_change_radiobutton->grid(-row=>0, -column=>1);
$ml_add_radiobutton->grid(-row=>0, -column=>2);
$ml_in_label->grid(-row=>1, -column=>1);
$ml_in_list->grid(-row=>2, -column=>0, -rowspan=>2, -columnspan=>3);
$ml_in_all_button->grid(-row=>2, -column=>3);
$ml_in_none_button->grid(-row=>3, -column=>3);

$ml_out2in_button->grid(-row=>4, -column=>1);
$ml_in2out_button->grid(-row=>5, -column=>1);

$ml_out_label->grid(-row=>6, -column=>1);
$ml_out_list->grid(-row=>7, -column=>0, -rowspan=>2, -columnspan=>3);
$ml_out_all_button->grid(-row=>7, -column=>3);
$ml_out_none_button->grid(-row=>8, -column=>3);

#$user_form->pack();
#$form_frame->pack();
#$movelist_frame->pack();
#$util_frame->pack();

sub repack_movelist_frame {
    $movelist_frame->pack(-side=>'right');
}
sub repack_form_frame {
    $form_frame->pack(-side=>'left', -fill=>'x', -anchor=>'n');
}
#### UTIL FUNCTIONS ####################################################################################
sub load_hash2MListbox {
    my $list = shift;
    my $hash_ref = shift;
    $list->delete(0, 'end');
    foreach my $key (keys(%{$hash_ref})) {
        $list->insert('end', [($key, $$hash_ref{$key})]);
    }
}


#### LOADING FUNCTIONS #################################################################################
sub select_user {
    my @selected = $users_list->curselection();
    $user_selc->clear();
    my $count = scalar @selected;
    if ($count  == 0) {
        #$user_selc->clear();
        setup_clear();
    }
    elsif ($count == 1) {
        $user_selc->insert(@selected);
        setup_user_mod($users_list->getRow($selected[0]));
    }
    else {
        $user_selc->insert(@selected);
        setup_user_multiplemod(map {($users_list->getRow($_))} $user_selc->members)
    }
    #
    #    if ($selected[0] == $user_selc) {
    #        $user_selc = -1;
    #        $users_list->selectionClear($selected[0]);
    #        setup_clear();
    #    }
    #    else {
    #        $user_selc=$selected[0];
    #        setup_user_mod($users_list->getRow($selected[0]));
    #    }
}

sub select_group {
    my @selected = $groups_list->curselection();

#    if ($selected[0] == $group_selc) {
#        $group_selc = -1;
#        $groups_list->selectionClear($selected[0]);
#        setup_clear();
#    }
#    else {
#        $group_selc=$selected[0];
#        setup_group_mod($groups_list->getRow($selected[0]));
#    }
    $group_selc->clear();
    my $count = scalar @selected;
    if ($count  == 0) {
        #$user_selc->clear();
        setup_clear();
    }
    elsif ($count == 1) {
        $group_selc->insert(@selected);
        setup_group_mod($groups_list->getRow($selected[0]));
    }
    else {
        $group_selc->insert(@selected);
        setup_group_multiplemod(map {$groups_list->getRow($_)} $group_selc->members)
    }
}


sub setup_clear {

    #wyczysc zaznaczenie obu list
    $users_list->selectionClear(0, 'end');
#    if (! $user_selc->is_empty()) {
#        foreach my $sel ($user_selc->members) {
#            $users_list->selectionClear($sel);
#        }
#    }
    $user_selc->clear();
    $groups_list->selectionClear(0, 'end');
#    if (! $group_selc->is_empty()) {
#        foreach my $sel ($group_selc->members) {
#            $groups_list->selectionClear($sel);
#       }
#    }
    $group_selc->clear();

    $ml_mode="none";
    $copy_dir = $default_copy_dir;
    $user_form->packForget();
    $group_form->packForget();
    $form_frame->packForget();
    $movelist_frame->packForget();

    printf "setup_clear"
}

sub clear_movable_lists {
    ML_empty_set();
    $ml_mode="none";
}

sub clear_user_form {

    unlock_user_form();
    unlock_movable_list();
    # wyczysc entries
    $u_entry_login->delete(0, 'end');
    $u_entry_uid->delete(0, 'end');
    $u_entry_pass->delete(0, 'end');
    $u_entry_rpass->delete(0, 'end');
    $u_entry_group->delete(0, 'end');
    $u_entry_home->delete(0, 'end');
    $u_entry_shell->delete(0, 'end');

    # wyczysc listy
    clear_movable_lists();
    unlock_movable_list();
    printf "clear_user_form\n"
}
sub setup_user_add {


    # zmiana widoku
    setup_clear();
    clear_user_form();

    $tabs->raise("users");
    $ml_mode="change";
    $ml_none_radiobutton->configure(-state=>"disabled");
    $ml_add_radiobutton->configure(-state=>"disabled");

    # load movabel lsit
    my @all_groups = keys %groups_name_gid;
    ML_load_set(@all_groups);

    $u_create_user_button->configure(-text=>'Create', -command=>\&try_add_user);


    printf "user_add_setup";

    #pokaz framey
    $user_form->pack();
    #$form_frame->pack();
    repack_form_frame();
    #$movelist_frame->pack();
    repack_movelist_frame();
}

sub try_remove_group {

    if ($tabs->raised() ne 'groups') {return -1};
    my @groups = map {($groups_list->getRow($_))[0]} $group_selc->members;
    if ( scalar(@groups) == 0) {return -1};
    my $str = join("', `", @groups);
    my $response = $mw->messageBox(-type=>'yescancel', -message=>"Do you rly want to delete groups: `$str'?",
        -icon=>'question');

    my $error = "";
    my $retr = "";
    if ($response eq "Yes") {
        foreach my $grp (@groups) {
           $retr = remove_group($grp, \$error);
           if ($retr != 0) {
                $mw->messageBox(-type=>'ok', -message=>"Cant delete user `$grp': $error");
           }
        }

        setup_clear();
    }
    return 0;

}

sub try_remove_user {

    if ($tabs->raised() ne 'users') {return -1};
    my @users = map {($users_list->getRow($_))[0]} $user_selc->members;
    if ( scalar(@users) == 0) {return -1};
    my $str = join("', `", @users);
    my $response = $mw->messageBox(-type=>'yescancel', -message=>"Do you rly want to delete users: `$str'?",
        -icon=>'question');

    my $error = "";
    my $retr = "";
    if ($response eq "Yes") {
        foreach my $usr (@users) {
           $retr = remove_user($usr, \$error);
           if ($retr != 0) {
                $mw->messageBox(-type=>'ok', -message=>"Cant delete user `$usr': $error");
           }
        }

        setup_clear();
    }
    return 0;

}
sub try_add_user {
    printf "\n\n\nDODAJEEEE\n\n\n";
    my %new_user_data = (
        'username'  => "",
        'pass'      => "",
        'rpass'     => "",
        'uid'       => "",
        'gid'       => "",
        'gecos'     => "",
        'homedir'   => "",
        'shell'     => "",
        'groups'    => [],
    );

    $new_user_data{'username'} = $u_entry_login->get();
    $new_user_data{'pass'} = $u_entry_pass->get();
    $new_user_data{'rpass'} = $u_entry_rpass->get();
    $new_user_data{'uid'} = $u_entry_uid->get();
    $new_user_data{'gid'} = $u_entry_group->get();
    $new_user_data{'homedir'} = $u_entry_home->get();
    $new_user_data{'shell'} = $u_entry_shell->get();
    push(@{$new_user_data{'groups'}}, $in_list_set->members);
    printf "Wypisuje\n";
    ddx(\%new_user_data);

    my $error = "";
    my $ret_val = add_user(\%new_user_data, \$error);

    if ($ret_val) {
        $mw->messageBox(-type => "ok", -message=> "$error");
        return -1;
    }

    setup_clear();
    $mw->messageBox(-type => "ok", -message=> "User `$new_user_data{'username'}' created");
}

sub setup_user_mod {

    #pobierz dane:
    my $username = shift;
    my ($pass, $uid, $gid, $gecos, $homedir, $shell) = $pw_file->user($username);


    my %rev_groups = reverse %groups_name_gid;
    my $main_group =  $rev_groups{$gid};
        #TODO

    my @groups = ();
    my @membs = ();
    my %pom_hash = ();
    foreach my $grp (keys %groups_name_gid) {
        if ($grp ne $main_group) {
            @membs = $grp_file->members($grp);
            if (scalar(@membs) > 0) {
                @pom_hash{@membs} = ();
                if (exists $pom_hash{$username}) {
                    printf "\n\n $grp \n\n";
                    push(@groups, $grp);
                }
                %pom_hash=();
        }

        }
    }
    printf "\nGID-> $gid\n\n";

    # zmiana widoku
    clear_user_form();
    $u_entry_login->insert(0, $username);
    $u_entry_uid->insert(0, $uid);
    $u_entry_group->insert(0, $gid);
    $u_entry_home->insert(0, $homedir);
    $u_entry_shell->insert(0, $shell);

    # load movabel lsit

    my @all_groups = map {$_ eq $main_group ? () : $_} keys %groups_name_gid;
    ML_load_set(@all_groups);
    ML_push_subset(@groups);

    # lock fileds

    lock_user_form();
    lock_movable_list();

    $u_create_user_button->configure(-text=>'Unlock', -command=>[\&allow_user_mod, $username]);

    $user_form->pack();
    #$form_frame->pack();
    repack_form_frame();
    #$movelist_frame->pack();
    repack_movelist_frame();


    printf "user_mod_setup";
}

sub try_mod_user {
    printf "\n\n\nMODYFIKUJEE USERA\n\n\n";
    my $oldusername = shift;
    my %mod_user_data = (
        'username'  => "",
        'pass'      => "",
        'rpass'      => "",
        'uid'       => "",
        'gid'       => "",
        'gecos'     => "",
        'homedir'   => "",
        'shell'     => "",
        'groups'    => [],
    );

    $mod_user_data{'username'} = $u_entry_login->get();
    $mod_user_data{'uid'} = $u_entry_uid->get();
    $mod_user_data{'pass'} = $u_entry_pass->get();
    $mod_user_data{'rpass'} = $u_entry_rpass->get();
    $mod_user_data{'gid'} = $u_entry_group->get();
    $mod_user_data{'homedir'} = $u_entry_home->get();
    $mod_user_data{'shell'} = $u_entry_shell->get();
    push(@{$mod_user_data{'groups'}}, $in_list_set->members);
    printf "Wypisuje\n";
    ddx(\%mod_user_data);

    my $error = "";
    my $ret_val = mod_user($oldusername, \%mod_user_data, \$error, $ml_mode);

    if ($ret_val) {
        $mw->messageBox(-type => "ok", -message=> "$error");
        return -1;
    }

    setup_clear();
    $mw->messageBox(-type => "ok", -message=> "User `$mod_user_data{'username'}' modificated");
}
sub setup_user_multiplemod {

    printf "@_\n";
    #return;
    #pobierz dane:
    my %usernames_uid = @_;


    # zmiana widoku
    clear_user_form();
    $u_entry_login->insert(0, join(', ', keys(%usernames_uid)));
    $u_entry_uid->insert(0, join(', ', values(%usernames_uid)));

    # load movabel lsit

    my @all_groups = keys %groups_name_gid;
    ML_load_set(@all_groups);

    # lock fileds

    lock_user_form();
    lock_movable_list();

    my @pom = keys %usernames_uid;
    $u_create_user_button->configure(-text=>'Unlock', -command=>[\&allow_user_multiplemod, @pom]);

    $user_form->pack();
    #$form_frame->pack();
    repack_form_frame();
    #$movelist_frame->pack();
    repack_movelist_frame();


    printf "user_multiplemod_setup";

}


sub try_multiplemod_user {
    printf "\n\n\nMODYFIKUJEE WIELU USEROW\n\n\n";
    my @usernames = @_;
    my %mod_user_data = (
        'username'  => "",
        'pass'      => "",
        'rpass'      => "",
        'uid'       => "",
        'gid'       => "",
        'gecos'     => "",
        'homedir'   => "",
        'shell'     => "",
        'groups'    => [],
    );

    $mod_user_data{'pass'} = $u_entry_pass->get();
    $mod_user_data{'rpass'} = $u_entry_rpass->get();
    $mod_user_data{'gid'} = $u_entry_group->get();
    $mod_user_data{'shell'} = $u_entry_shell->get();
    push(@{$mod_user_data{'groups'}}, $in_list_set->members);
    printf "Wypisuje\n";
    ddx(\%mod_user_data);

    my @mod_users = ();
    my $ret_val = "";
    my $error = "";
    foreach my $username (@usernames) {
        $mod_user_data{'username'} = $username;
        $ret_val = mod_user($username, \%mod_user_data, \$error, $ml_mode);

        if ($ret_val) {
            $mw->messageBox(-type => "ok", -message=> "In user `$username' modification: $error");
        }
        else {
            push(@mod_users, $username);
        }
    }

    if (scalar(@mod_users) == 0) {
        $mw->messageBox(-type => "ok", -message=> "No users modificated");
        return -1;
    }
    setup_clear();
    my $str = join("', `", @mod_users);
    $mw->messageBox(-type => "ok", -message=> "Users `$str' modificated");
}

sub allow_user_multiplemod {
    my @usernames = @_;
    unlock_user_form();
    $u_entry_login->configure(-state=>'readonly');
    $u_entry_uid->configure(-state=>'readonly');
    $u_entry_home->configure(-state=>'disabled');
    unlock_movable_list_radiobuttons();
    $u_create_user_button->configure(-text=>'Save', -command=>[\&try_multiplemod_user, @usernames]);
}


sub allow_user_mod {
    my $username = shift;
    unlock_user_form();
    unlock_movable_list_radiobuttons();
    $u_create_user_button->configure(-text=>'Save', -command=>[\&try_mod_user, $username]);
}

sub lock_user_form {
    $u_entry_login->configure(-state=>'disabled');
    $u_entry_uid->configure(-state=>'disabled');
    $u_entry_pass->configure(-state=>'disabled');
    $u_entry_rpass->configure(-state=>'disabled');
    $u_entry_group->configure(-state=>'disabled');
    $u_entry_home->configure(-state=>'disabled');
    $u_entry_shell->configure(-state=>'disabled');


}

sub unlock_user_form {
    $u_entry_login->configure(-state=>'normal');
    $u_entry_uid->configure(-state=>'normal');
    $u_entry_pass->configure(-state=>'normal');
    $u_entry_rpass->configure(-state=>'normal');
    $u_entry_group->configure(-state=>'normal');
    $u_entry_home->configure(-state=>'normal');
    $u_entry_shell->configure(-state=>'normal');

}


sub setup_user_del {
    printf "user_del_setup"
}


# GRUP

sub clear_group_form {
    unlock_group_form();
    unlock_movable_list();
    # wyczysc entries
    $g_entry_name->delete(0, 'end');
    $g_entry_gid->delete(0, 'end');

    # wyczysc listy
    clear_movable_lists();
    printf "clear_user_form\n"
}

sub setup_group_add {


    # zmiana widoku
    setup_clear();
    clear_group_form();


    $tabs->raise("groups");
    $ml_mode="change";
    $ml_none_radiobutton->configure(-state=>"disabled");
    $ml_add_radiobutton->configure(-state=>"disabled");


    # load movabel lsit
    my @all_users = keys %users_name_uid;
    ML_load_set(@all_users);

    $g_create_group_button->configure(-text=>'Create', -command=>\&try_add_group);

    $group_form->pack();
    #$form_frame->pack();
    repack_form_frame();
    #$movelist_frame->pack();
    repack_movelist_frame();

    printf "group_add_setup"
}

sub try_mod_group {
    printf "\n\n\nMODYFIKUJEE GRUPE\n\n\n";
    my $oldgroupname = shift;
    my %mod_group_data = (
        'groupname' => "",
        'pass'      => "",
        'gid'       => "",
        'users'     => [],
    );

    $mod_group_data{'groupname'} = $g_entry_name->get();
    $mod_group_data{'gid'} = $g_entry_gid->get();
    push(@{$mod_group_data{'users'}}, $in_list_set->members);

    printf "Wypisuje\n";
    ddx(\%mod_group_data);

    my $error = "";
    my $ret_val = mod_group($oldgroupname, \%mod_group_data, \$error, $ml_mode);


    if ($ret_val) {
        $mw->messageBox(-type => "ok", -message=> "$error");
        return -1;
    }

    setup_clear();
    $mw->messageBox(-type => "ok", -message=> "Group `$mod_group_data{'groupname'}' modificated");
}

sub try_multiplemod_group {
    printf "\n\n\nMODYFIKUJEE WIELE GRUP\n\n\n";
    my @gropnames = @_;
    my %mod_group_data = (
        'groupname' => "",
        'pass'      => "",
        'gid'       => "",
        'users'     => [],
    );

    push(@{$mod_group_data{'users'}}, $in_list_set->members);

    printf "Wypisuje\n";
    ddx(\%mod_group_data);
    ddx(\@gropnames);

    my @mod_groups = ();
    my $ret_val = "";
    my $error = "";

    foreach my $groupname (@gropnames) {
        $mod_group_data{'groupname'} = $groupname;
        $ret_val = mod_group($groupname, \%mod_group_data, \$error, $ml_mode);

        if ($ret_val) {
            $mw->messageBox(-type => "ok", -message=> "$error");
        }
        else {
            push(@mod_groups, $groupname);
        }
    }

    if (scalar(@mod_groups) == 0) {
        $mw->messageBox(-type => "ok", -message=> "No groups modificated");
        return -1;
    }
    setup_clear();
    my $str = join("', `", @mod_groups);
    $mw->messageBox(-type => "ok", -message=> "Groups `$str' modificated");
}

sub try_add_group {
    printf "\n\n\nDODAJEEEE GRUPE\n\n\n";
    my %new_group_data = (
        'groupname' => "",
        'pass'      => "",
        'gid'       => "",
        'users'     => [],
    );

    $new_group_data{'groupname'} = $g_entry_name->get();
    $new_group_data{'gid'} = $g_entry_gid->get();
    push(@{$new_group_data{'users'}}, $in_list_set->members);
    printf "Wypisuje\n";
    ddx(\%new_group_data);

    my $error = "";
    my $ret_val = add_group(\%new_group_data, \$error);
    printf "$error\n";
    if ($ret_val) {
        $mw->messageBox(-type => "ok", -message=> "$error");
        return -1;
    }

    setup_clear();
    $mw->messageBox(-type => "ok", -message=> "Group `$new_group_data{'groupname'}' created");

}

sub setup_group_mod {

    #pobierz dane:
    my $groupname = shift;
    my $gid = $groups_name_gid{$groupname};
    my @users = $grp_file->members($groupname);

    # zmiana widoku
    clear_group_form();
    $g_entry_name->insert(0, $groupname);
    $g_entry_gid->insert(0, $gid);

    # load movabel lsit

    my @all_users = keys %users_name_uid;
    ML_load_set(@all_users);
    ML_push_subset(@users);

    # lock fileds

    lock_group_form();
    lock_movable_list();

    $g_create_group_button->configure(-text=>'Unlock', -command=>[\&allow_group_mod, $groupname]);

    $group_form->pack();
    #$form_frame->pack();
    repack_form_frame();
    #$movelist_frame->pack();
    repack_movelist_frame();


    printf "group_mod_setup";
}


sub setup_group_multiplemod {

    printf "@_\n";
    #return;
    #pobierz dane:
    my %groupnames_gid = @_;


    # zmiana widoku
    clear_group_form();
    $g_entry_name->insert(0, join(', ', keys(%groupnames_gid)));
    $g_entry_gid->insert(0, join(', ', values(%groupnames_gid)));

    # load movabel lsit

    my @all_users = keys %users_name_uid;
    ML_load_set(@all_users);

    # lock fileds

    lock_group_form();
    lock_movable_list();

    my @pom = keys %groupnames_gid;
    $g_create_group_button->configure(-text=>'Unlock', -command=>[\&allow_group_multiplemod, @pom]);

    $group_form->pack();
    #$form_frame->pack();
    repack_form_frame();
    $movelist_frame->pack();

}
sub allow_group_multiplemod {
    my @groupnames = @_;
    unlock_group_form();
    $g_entry_name->configure(-state=>'readonly');
    $g_entry_gid->configure(-state=>'readonly');
    unlock_movable_list_radiobuttons();
    $g_create_group_button->configure(-text=>'Save', -command=>[\&try_multiplemod_group, @groupnames]);
}

sub allow_group_mod {
    my $groupname = shift;
    unlock_group_form();
    unlock_movable_list_radiobuttons();
    $g_create_group_button->configure(-text=>'Save', -command=>[\&try_mod_group, $groupname]);
}

sub lock_group_form {
    $g_entry_name->configure(-state=>'disabled');
    $g_entry_gid->configure(-state=>'disabled');

}

sub unlock_group_form {
    $g_entry_name->configure(-state=>'normal');
    $g_entry_gid->configure(-state=>'normal');
}

sub setup_group_del {
    printf "group_del_setup"
}

#### MOVABLE LIST FUNCTIONS #####################################################################

sub lock_movable_list_radiobuttons {
    $ml_mode='none';
    $ml_none_radiobutton->configure(-state=>'disabled');
    $ml_change_radiobutton->configure(-state=>'disabled');
    $ml_add_radiobutton->configure(-state=>'disabled');
}

sub unlock_movable_list_radiobuttons {

    $ml_mode='none';
    if (scalar(@_) > 0) {
        $ml_mode = shift;
    }
    $ml_none_radiobutton->configure(-state=>'normal');
    $ml_change_radiobutton->configure(-state=>'normal');
    $ml_add_radiobutton->configure(-state=>'normal');
}

sub lock_movable_list_rest {
    $ml_in_list->configure(-state=>'disabled');
    $ml_out_list->configure(-state=>'disabled');

    $ml_in2out_button->configure(-state=>'disabled');
    $ml_out2in_button->configure(-state=>'disabled');

    $ml_in_all_button->configure(-state=>'disabled');
    $ml_out_all_button->configure(-state=>'disabled');

    $ml_in_none_button->configure(-state=>'disabled');
    $ml_out_none_button->configure(-state=>'disabled');

}

sub unlock_movable_list_rest {
    $ml_in_list->configure(-state=>'normal');
    $ml_out_list->configure(-state=>'normal');

    $ml_in2out_button->configure(-state=>'normal');
    $ml_out2in_button->configure(-state=>'normal');

    $ml_in_all_button->configure(-state=>'normal');
    $ml_out_all_button->configure(-state=>'normal');

    $ml_in_none_button->configure(-state=>'normal');
    $ml_out_none_button->configure(-state=>'normal');


}
sub lock_movable_list {
    lock_movable_list_radiobuttons();
    lock_movable_list_rest();
}

sub unlock_movable_list {
    unlock_movable_list_radiobuttons(@_);
    unlock_movable_list_rest();
}

sub move_selection {
    my($from_list, $to_list, $flag) = @_;
    my @moved_ids = $from_list->curselection();
    if (scalar(@moved_ids) == 0) {
        return;
    }

    my @moved_strs = map {$from_list->get($_)} @moved_ids;

    printf "\n\n ruszane @moved_strs.split(' ')\n\n";
    if ($flag == 1) {
        ML_push_subset(@moved_strs);
    }
    elsif ($flag == 0) {
        ML_pop_subset(@moved_strs);
    }
}

sub ML_load_set {
    my @values = @_;
    if (scalar(@values) == 0 ) {
        printf "pusty zbior w ML_load_set";
        return;
    }
    $out_list_set->insert(@values);
    $in_list_set->clear();


    $ml_in_list->delete(0, 'end');
    $ml_out_list->delete(0, 'end');
    $ml_out_list->insert(0,$out_list_set->members);
    $ml_in_list->insert(0,$in_list_set->members);
}

sub ML_push_subset {
    my @values = @_;
    if (scalar(@values) == 0 ) {
        printf "pusty zbior w ML_push_subset";
        return;
    }
    my $subset = Set::Scalar->new(@values);
    if (! ($subset <= $out_list_set) ) {
        printf "UWAGA! w ML_push_subset to nie jest pozbior out_list_set\n";
        return;
    }

    if ( (! ($subset != $in_list_set)) && (! ($in_list_set->is_empty())) )  {
        printf "UWAGA! w ML_push_subset nie jest rozlaczny z in_list_set\n";
        return;
    }

    $out_list_set = $out_list_set / $subset;
    $in_list_set = $in_list_set + $subset;


    $ml_in_list->delete(0, 'end');
    $ml_out_list->delete(0, 'end');
    printf "PUSH -> chce insertowac to:\n $out_list_set\n $in_list_set\n";
    $ml_out_list->insert('end', $out_list_set->members);
    $ml_in_list->insert('end', $in_list_set->members);

}

sub ML_pop_subset {
    my @values = @_;
    if (scalar(@values) == 0 ) {
        printf "pusty zbior w ML_pop_subset";
        return;
    }

    my $subset = Set::Scalar->new(@values);
    if (! ($subset <= $in_list_set) ) {
        printf "UWAGA! w ML_pop_subset to nie jest pozbior in_list_set\n";
        return;
    }

    if ( (! ($subset != $out_list_set)) && (! ($out_list_set->is_empty())) ) {
        printf "UWAGA! w ML_pop_subset nie jest rozlaczny z out_list_set\n";
        return;
    }


    $out_list_set = $out_list_set + $subset;
    $in_list_set = $in_list_set / $subset;

    $ml_in_list->delete(0, 'end');
    $ml_out_list->delete(0, 'end');
    printf "POP -> chce insertowac to:\n $out_list_set\n $in_list_set\n";
    $ml_out_list->insert('end', $out_list_set->members);
    $ml_in_list->insert('end', $in_list_set->members);
}

sub ML_empty_set {
    $in_list_set->clear();
    $ml_in_list->delete(0, 'end');
    $out_list_set->clear();
    $ml_out_list->delete(0, 'end');
}



#### LOGIC FUNCTIONS ############################################################################


## USER >>>

sub mod_user {
    my($oldusername, $data_hash_ref, $error_ref, $mode) = @_;
    my %data_hash = %{$data_hash_ref};

    if (! defined($users_name_uid{$oldusername})) {
        printf "\n\n\nPOWAZNY BLAD $oldusername NIE ISTNIEJE\n\n";
    }

    my($oldpass, $olduid, $oldgid, $oldgecos, $oldhomedir, $oldshell) =
        $pw_file->user($oldusername);

    my %old_user_data = (
        'username'  => "$oldusername",
        'uid'       => "$olduid",
        'gid'       => "$oldgid",
        'gecos'     => "$oldgecos",
        'homedir'   => "$oldhomedir",
        'shell'     => "$oldshell",
    );

    my %changed_user_data = %data_hash;


    foreach my $key (keys %old_user_data) {
        if ($old_user_data{$key} eq $data_hash{$key}) {
            $changed_user_data{$key} = "";
        }
    }

    if (( $data_hash{'pass'} eq "") && ($data_hash{'rpass'} eq "")) {
        $changed_user_data{'pass'} = "";
    }
    elsif ($data_hash{'pass'} eq "*") {
        $changed_user_data{'pass'} = gen_random_pass(5);
    }
    elsif ($data_hash{'pass'} ne $data_hash{'rpass'}) {
        $$error_ref = "PASSWORD not equal";
        $changed_user_data{'pass'} = "";
        return 2;
    }
    elsif (! isValidPassword($data_hash{'pass'})) {
        $$error_ref = "PASSWORD is not valid";
        $changed_user_data{'pass'} = "";
        return 2;
    }



    if ($changed_user_data{'username'} ne "") {
        if (defined($users_name_uid{$changed_user_data{'username'}})) {
            $$error_ref = "User `$changed_user_data{'username'}' already exists";
            $changed_user_data{'username'} = "";
            return 1;
        }
        elsif (! isValidUsername($data_hash{'username'})) {
            $$error_ref = "Username `$data_hash{'username'}' is invalid";
            $changed_user_data{'username'} = "";
            return 1;
        }
    }

    if ($changed_user_data{'uid'} ne "") {
        if (! isValidId($data_hash{'uid'})) {
            $$error_ref = "UID $data_hash{'uid'}' is invalid";
            $changed_user_data{'uid'} = "";
            return 3;
        }
        foreach my $key (keys(%users_name_uid)) {
            if ($users_name_uid{$key} == $data_hash{'uid'}) {
                $$error_ref = "UID $data_hash{'uid'}' already exists";
                $changed_user_data{'uid'} = "";
                return 3;
            }
        }
    }

    my $oldgroup = "";
    my $newgroup = "";
    if ($changed_user_data{'gid'} ne "") {
        if (! isValidId($data_hash{'gid'})) {
            $$error_ref = "GID $data_hash{'gid'}' is invalid";
            $changed_user_data{'gid'} = "";
            return 4;
        }

        my %rew_groups = reverse %groups_name_gid;
        if (! defined($rew_groups{$data_hash{'gid'}})) {
            $$error_ref = "GID $data_hash{'gid'}' does not exist";
            $changed_user_data{'gid'} = "";
            return 4;
        }
        else {
            $oldgroup = $rew_groups{$oldgid};
            $newgroup = $rew_groups{$data_hash{'gid'}};
        }
    }

    my $curr_username = $oldusername;


    if ($mode eq 'change') {
        $grp_file->remove_user("*", $curr_username);
        $grp_file->commit();
        $grp_file->add_user($oldgroup, $curr_username);
        $grp_file->commit();
    }
    if ( ($mode eq 'change') || ($mode eq 'add') ) {
        foreach my $group (@{$data_hash{'groups'}}) {
            $grp_file->add_user($group, $curr_username);
        }
        $grp_file->commit();
    }

    if ($changed_user_data{'username'}) {
        if ($pw_file->rename($oldusername, $changed_user_data{'username'})) {
            $curr_username = $changed_user_data{'username'};
            $grp_file->rename_user($oldusername, $changed_user_data{'username'});
            $pw_file->commit();
            $pw_file->gecos($curr_username, $curr_username);
            $grp_file->commit();
        }
        else {$curr_username = $oldusername; $changed_user_data{'username'} = "";};
    }

    if ($changed_user_data{'uid'}) {
        $pw_file->uid($curr_username, $changed_user_data{'uid'});
        $pw_file->commit();
    }

    if ($changed_user_data{'gid'}) {
        $pw_file->gid($curr_username, $changed_user_data{'gid'});
        $pw_file->commit();
        $grp_file->remove_user($oldgroup, $curr_username);
        $grp_file->add_user($newgroup, $curr_username);
        $grp_file->commit();
    }

    my $curr_homedir = $oldhomedir;
    if ($changed_user_data{'homedir'}) {
        if (! create_homedir($changed_user_data{'homedir'})) {
            $changed_user_data{'homedir'} = $oldhomedir;
        }
        else {
            $curr_homedir = $changed_user_data{'homedir'};
            move_homedir($oldhomedir, $changed_user_data{'homedir'});
            $pw_file->home($curr_username, $changed_user_data{'homedir'});
            $pw_file->commit();
        }
    }

    if ($changed_user_data{'shell'}) {
        $pw_file->shell($curr_username, $changed_user_data{'shell'});
        $pw_file->commit();
    }

    if (($changed_user_data{'uid'} ne "")
        || ($changed_user_data{'gid'} ne "")
        || ($curr_homedir ne $oldhomedir)) {

        my $nuid = $changed_user_data{'uid'};
        $nuid = $olduid if ($changed_user_data{'uid'} eq "");
        my $ngid = $changed_user_data{'gid'};
        $ngid = $oldgid if ($changed_user_data{'gid'} eq "");

        my $ouid = $olduid;
        $ouid = -1 if ($curr_homedir ne $oldhomedir);
        my $ogid = $oldgid;
        $ogid = -1 if ($curr_homedir ne $oldhomedir);

        printf "\n\n TAK ZMIEN MNIE z ${ouid}.${ogid} na ${nuid}.${ngid}\n\n";
        change_user_group_in_homedir($nuid, $ouid, $ngid, $ogid, $curr_homedir);
    }
    change_password_record($sh_desc, $oldusername,
        $changed_user_data{'username'},
        $changed_user_data{'pass'});


    my $old_pass = "?";
    if (defined($log_data{$oldusername})) {
        $old_pass = $log_data{$oldusername}->{'password'};
    }
    delete_user_from_log($oldusername);
    my $write_username = $oldusername;
    if ($changed_user_data{'username'} ne "") {
        $write_username = $changed_user_data{'username'};
    }
    my $write_uid = $olduid;
    if ($changed_user_data{'uid'} ne "") {
        $write_uid = $changed_user_data{'uid'};
    }
    my $write_pass = $old_pass;
    if ($changed_user_data{'pass'} ne "") {
        $write_pass = $changed_user_data{'pass'};
    }

    write_user_to_log($write_username, $write_uid, $write_pass);

    load_groups();
    load_users();
    load_hash2MListbox($users_list, \%users_name_uid);
    load_hash2MListbox($groups_list, \%groups_name_gid);
    return 0;
}


sub add_user {
    my($data_hash_ref, $error_ref) = @_;
    my %data_hash = %{$data_hash_ref};

    # nazwa juz istnieje
    if (defined($users_name_uid{$data_hash{'username'}})) {
        $$error_ref = "User `$data_hash{'username'}' already exists";
        return 1;
    }

    # czy nazwa moze byc uzyta?
    if (! isValidUsername($data_hash{'username'})) {
        $$error_ref = "Login `$data_hash{'username'}' is invalid";
        return 1;
    }

    # uid juz istnieje
    if ($data_hash{'uid'} eq "") {
        $data_hash{'uid'} = $pw_file->maxuid("60000") + 1;
    }
    elsif (! isValidId($data_hash{'uid'})) {
        $$error_ref = "UID `$data_hash{'uid'}' is not valid";
        return 3;
    }

    foreach my $key (keys(%users_name_uid)) {
        if ($users_name_uid{$key} == $data_hash{'uid'}) {
            $$error_ref = "UID $data_hash{'uid'}' already exists";
            return 3;
        }
    }

    if ($data_hash{'gid'} eq "") {
        $data_hash{'gid'} = $data_hash{'uid'};
    }
    elsif (! isValidId($data_hash{'gid'})) {
        $$error_ref = "GID `$data_hash{'gid'}' is not valid";
        return 4;
    }


    my $err;
    my $new_group_data = {
        'groupname' => "$data_hash{'username'}",
        'pass'      => "*",
        'gid'       => "$data_hash{'gid'}",
        'users'     => ["$data_hash{'username'}"],
    };
    my $status = add_group($new_group_data, \$err);
    if ( $status == 1) {
        $data_hash{'gid'} = $groups_name_gid{$data_hash{'username'}};
    }
    elsif ( $status == 3) {
        #$data_hash{'gid'} = $grp_file->maxgid("60000") + 1;
        $data_hash{'gid'} = get_free_gid(60000);
        $$new_group_data{'gid'} = $data_hash{'gid'};
        add_group($new_group_data, \$err);

    }
    elsif ( $status == 0 ) {
        $data_hash{'gid'} = $data_hash{'uid'};
    }


    # DEFAULTS:
    if (( $data_hash{'pass'} eq "") && ($data_hash{'rpass'} eq "")) {
        $data_hash{'pass'} = gen_random_pass(5);
    }
    elsif ($data_hash{'pass'} ne $data_hash{'rpass'}) {
        $$error_ref = "PASSWORD not equal";
        return 2;
    }
    elsif (! isValidPassword($data_hash{'pass'})) {
        $$error_ref = "PASSWORD is not valid";
        return 2;
    }

    if ($data_hash{'gecos'} eq "") {
        $data_hash{'gecos'} = $data_hash{'username'};
    }
    if ($data_hash{'homedir'} eq "") {
        $data_hash{'homedir'} = "/home/$data_hash{'username'}";
    }

    if (! create_homedir($data_hash{'homedir'})) {
        $$error_ref = "HOMEDIR path $data_hash{'homedir'} is not valid";
        return 2;
    }

    if ($data_hash{'shell'} eq "") {
        $data_hash{'shell'} = "/bin/sh";
    }

    if (! add_password_record($sh_desc, $data_hash{'username'}, $data_hash{'pass'})) {
        $$error_ref = "PASSWORD couldnt be written to shadow file";
        return 256;
    }
    my $out = $pw_file->user(
        $data_hash{'username'},
        "x",
        $data_hash{'uid'},
        $data_hash{'gid'},
        $data_hash{'gecos'},
        $data_hash{'homedir'},
        $data_hash{'shell'});

    $pw_file->commit();

    copy_to_homedir($data_hash{'homedir'}, $copy_dir);
    write_user_to_log($data_hash{'username'}, $data_hash{'uid'}, $data_hash{'pass'});

    foreach my $group (@{$data_hash{'groups'}}) {
        $grp_file->add_user($group, $data_hash{'username'});
    }

    $grp_file->commit();

    change_user_group_in_homedir($data_hash{'uid'}, "-1", $data_hash{'gid'}, "-1", $data_hash{'homedir'});
    #reload files
    load_groups();
    load_users();
    load_hash2MListbox($users_list, \%users_name_uid);
    load_hash2MListbox($groups_list, \%groups_name_gid);

    return 0;
}

sub remove_user {
    my ($username, $error_ref) = @_;

    if ( ! defined($users_name_uid{$username})) {
        $$error_ref = "User `$username' doesn't exists";
        return 1;
    }

    # usun z pliku passwd
    $pw_file->delete($username);
    $pw_file->commit();

    # usun z pliku group
    if ($grp_file->remove_user('*', $username) != 1) {
        print "\n\nBLAD W USUWANIU\n\n";
    }
    $grp_file->commit();

    del_password_record($sh_desc, $username);
    delete_user_from_log($username);
    load_users();
    load_groups();
    load_hash2MListbox($users_list, \%users_name_uid);
    load_hash2MListbox($groups_list, \%groups_name_gid);
    return 0;

    print "remove user"
}


## <<< USER

## GRUP >>>
sub mod_group {
    my($oldgroupname, $data_hash_ref, $error_ref, $mode) = @_;
    my %data_hash = %{$data_hash_ref};

    if (! defined($groups_name_gid{$oldgroupname})) {
        printf "\n\n\nPOWAZNY BLAD $oldgroupname NIE ISTNIEJE\n\n";
    }

    my($oldpass, $oldgid, @oldusers) =
        $grp_file->group($oldgroupname);

    my %old_group_data = (
        'groupname'  => "$oldgroupname",
        'pass'      => "$oldpass",
        'gid'       => "$oldgid",
    );

    my %changed_group_data = %data_hash;


    foreach my $key (keys %old_group_data) {
        if ($old_group_data{$key} eq $data_hash{$key}) {
            $changed_group_data{$key} = "";
        }
    }

    if ($changed_group_data{'groupname'} ne "") {
    # nazwa juz istnieje
        if (defined($groups_name_gid{$data_hash{'groupname'}})) {
            $$error_ref = "Group `$data_hash{'groupname'} already exists";
            $changed_group_data{'groupname'} = "";
            return 1;
        }

        # czy nazwa moze byc uzyta?
        if (! isValidGroupname($data_hash{'groupname'})) {
            $$error_ref = "Group `$data_hash{'groupname'} is invalid";
            $changed_group_data{'groupname'} = "";
            return 1;
        }
    }

    if ($changed_group_data{'gid'} ne "") {
        if (! isValidId($data_hash{'gid'})) {
            $$error_ref = "GID $data_hash{'gid'}' is invalid";
            $changed_group_data{'gid'} = "";
            return 3;
        }

        foreach my $key (keys(%groups_name_gid)) {
            if ($groups_name_gid{$key} == $data_hash{'gid'}) {
                $$error_ref = "GID $data_hash{'gid'}' already exists";
                $changed_group_data{'gid'} = "";
                return 3;
            }
        }
    }

    if ($mode ne 'none') {
        my $newusers_set = Set::Scalar->new(@{$data_hash{'users'}});
        my $oldusers_set = Set::Scalar->new(@oldusers);
        if ($mode eq 'change') {
            my $deleted = $oldusers_set - $newusers_set;
            my $added = $newusers_set - $oldusers_set;
            #$mw->messageBox(-type=>'ok', -message=> "new: $newusers_set\n old: $oldusers_set\n del: $deleted\n add:$added");

            foreach my $usr ($deleted->members) {
                my $ugid = $pw_file->gid($usr);
                if ($ugid == $oldgid) {
                    next;
                }
                $grp_file->remove_user($oldgroupname, $usr);
                $grp_file->commit();
            }
            foreach my $usr ($added->members) {
                $grp_file->add_user($oldgroupname, $usr);
                $grp_file->commit();
            }
        }
        if ($mode eq 'add') {
            foreach my $usr ($newusers_set->members) {
                $grp_file->add_user($oldgroupname, $usr);
                $grp_file->commit();
            }

        }
    }

    my $curr_groupname = $oldgroupname;
    if ($changed_group_data{'groupname'}) {
        my ($cur_pass, $cur_gid, $cur_users) = $grp_file->group($curr_groupname);
        $grp_file->delete($curr_groupname);
        $grp_file->commit();
        $grp_file->group($changed_group_data{'groupname'}, $cur_pass, $cur_gid, $cur_users);
        $curr_groupname = $data_hash{'groupname'};
        $grp_file->commit();
    }

    if ($changed_group_data{'gid'}) {
            $grp_file->gid($curr_groupname, $data_hash{'gid'});
            $grp_file->commit();
            foreach my $usr ($grp_file->members($curr_groupname)) {
                $pw_file->gid($usr, $data_hash{'gid'});
            }
            $pw_file->commit();
    }
    load_groups();
    load_users();
    load_hash2MListbox($users_list, \%users_name_uid);
    load_hash2MListbox($groups_list, \%groups_name_gid);
    return 0;

}




sub add_group {
    my($data_hash_ref, $error_ref) = @_;
    my %data_hash = %{$data_hash_ref};

    # nazwa juz istnieje
    if (defined($groups_name_gid{$data_hash{'groupname'}})) {
        $$error_ref = "Group `$data_hash{'groupname'} already exists";
        return 1;
    }

    # czy nazwa moze byc uzyta?
    if (! isValidGroupname($data_hash{'groupname'})) {
        $$error_ref = "Group `$data_hash{'groupname'} is invalid";
        return 1;
    }

    # gid juz istnieje
    if ($data_hash{'gid'} eq "") {
        #$data_hash{'gid'} = $grp_file->maxgid("60000") + 1;
        $data_hash{'gid'} = get_free_gid("60000");
    }
    elsif (! isValidId($data_hash{'gid'})) {
        $$error_ref = "GID $data_hash{'gid'}' is invalid";
        return 3;
    }


    foreach my $key (keys(%groups_name_gid)) {
        if ($groups_name_gid{$key} == $data_hash{'gid'}) {
            $$error_ref = "GID $data_hash{'gid'}' already exists";
            return 3;
        }
    }

    # DEFAULTS:
    if (($data_hash{'pass'} eq "") || ($data_hash{'pass'} eq "*")) {
        $data_hash{'pass'} = "*";
    }
    else {
        $data_hash{'pass'} = $grp_file->encpass($data_hash{'pass'});
    }

    my $out = $grp_file->group(
        $data_hash{'groupname'},
        $data_hash{'pass'},
        $data_hash{'gid'},
        @{$data_hash{'users'}});
    $grp_file->commit();

    load_groups();
    load_users();
    load_hash2MListbox($users_list, \%users_name_uid);
    load_hash2MListbox($groups_list, \%groups_name_gid);
    return 0;

}
sub remove_group {
    my($groupname, $error_ref) = @_;

    if ( !defined($groups_name_gid{$groupname})) {
        $$error_ref = "Group `$groupname' doesn't exists";
        return 1;
    }

    my $gid = $groups_name_gid{$groupname};

    # sprawdz czy nie jest glowna grupa

    foreach my $key (keys(%users_name_uid)) {
        my $ugid = $pw_file->gid($key);
        if ($ugid == $gid) {
            $$error_ref = "Group $groupname is primary for user $key";
            return 1;
        }
    }

    $grp_file->delete($groupname);
    $grp_file->commit();


    load_users();
    load_groups();
    load_hash2MListbox($users_list, \%users_name_uid);
    load_hash2MListbox($groups_list, \%groups_name_gid);
    return 0;

}

## <<< GRUP

sub isValidUsername {
    my $name = shift;
    if ($name =~ m/^[a-z][-a-z0-9]*$/) {
        return 1;
    }
    return 0;
}

sub isValidGroupname {
    my $name = shift;
    if ($name =~ m/^[a-z][-a-z0-9]*$/) {
        return 1;
    }
    return 0;
}


sub isValidPassword {
    my $pass = shift;
    if (length($pass) >= 4) {
        return 1;
    }
    return 0;
}

sub isValidId {
    my $id = shift;
    if ($id =~ m/^\d+$/) {
        my $vid = int($id);
        if (($vid >= 1000) && ($vid <= 65534)) {
            return 1;
        }
    }
    return 0;
}

########################################## UTIL #################################################################

################# HOMEDIR ####################
sub create_homedir {
    my $homedir = shift;
    if ($homedir eq "/") {return 0};
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
    my ($homedir, $copy_from) = @_;
    my @errors = ();
    if (! -e "$homedir") {
        printf STDERR "Direcotry `$homedir' does not exist\n";
        return 0;
    }
    my $from = File::Spec->catfile("$copy_from");
    $from = quotemeta($from);
    rcopy_glob("${from}/.??*", "$homedir");
    return 1;
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

####################### PASS ##########################################

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
    my $val = Time::Seconds->new(time);
    #return int(time / (60 * 60 * 24));
    return int($val->days);
}

###################################### SHADOW #####################################
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
    return 1;
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
        #printf "user-> $1\npass-> $2\ndays-> $3\nrest-> $4\n";
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


sub get_free_gid {
    my $ignore = shift;
    my %gid_group = reverse %groups_name_gid;
    for (my $i = 1000; $i < $ignore; $i++) {
        if (! defined($gid_group{$i})) {
            return $i;
        }
    }

}
##################################################################################################################
########                                                                                                ##########
########                                          MAIN                                                  ##########
########                                                                                                ##########
##################################################################################################################

#my $qwe = add_user('zgrupami2','', '1236', '1236', 'Zbynio', '', '',['boozers', 'pawel'], \$error);
#printf "$qwe -> $error\n";

#ML_load_set(qw/1 2 3 4 4/);
#ML_push_subset(qw/2 4/);
#print $out_list_set;
#print $in_list_set;
#ML_pop_subset(qw/2 4/);
#print $out_list_set;
#print $in_list_set;
#exit 0;
sub exit_users {
    close_data_files();
    save_log();
}
sub CLEANUP {
    exit_users;
    exit (1);
}
END {
    exit_users;
}

open_data_files();
load_log();
load_users();
load_groups();
load_hash2MListbox($users_list, \%users_name_uid);
load_hash2MListbox($groups_list, \%groups_name_gid);

MainLoop;
exit 0;

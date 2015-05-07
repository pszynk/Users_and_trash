#!/usr/bin/perl -w
use strict;
use warnings;
use DB_File;
use Fcntl;
use Getopt::Long;
use File::stat;
use Time::localtime;
use Mail::Box::Manager;
use Text::Table;
use Encode;
use utf8;
no utf8;
use utf8;
no utf8;

#---------------------------------------------------------------------
# SZABLONY >>

# nawias ogólny używany w kodowaniu hash -> string
my %BRACKETS = (
    '(' => '<%&',
    ')' => '&%>',
);

# nawias okalający maile w kodowaniu hash -> string
my %ADDRESS_BRACKETS = (
    '(' => '\[',
    ')' => '\]',
);

# znaczniki otaczające kolumny w kodowaniu hash -> string;
my %COLUMNS = (
    'msgId'     =>  {
            '('     => 'MSGID',
            ')'     => 'DIGSM',
    },
    'msgSub'    =>  {
            '('     => 'MSGSUB',
            ')'     => 'BUSGSM',
    },
    'msgFrom'   =>  {
            '('     =>  'MSGFROM',
            ')'     =>  'MORFGSM',
    },
    'msgTo'     =>  {
            '('     =>  'MSGTO',
            ')'     =>  'OTGSM',
    },
    'folder'    =>  {
            '('     =>  'FOLDER',
            ')'     =>  'REDLOF',
    },
    'msgNr'    =>  {
            '('     =>  'MSGNR',
            ')'     =>  'RNGSM',
    },
    'dirty'    =>   {
            '('     =>  'DIRTY',
            ')'     =>  'YTRID',
    },
);

# kolejność wartości stanowiących klucz w kodowaniu hash -> string
my @KEY_COLUMN = ('msgId', 'msgSub', 'msgFrom', 'msgTo');
# kolejność wartości stanowiących wartość w kodowaniu hash -> string
my @VALUE_COLUMN = ('folder', 'msgNr', 'dirty');

my %TABLE_COLUMN_NAMES = (
    'msgId'     => 'Message id:',
    'msgSub'    => 'Subject:',
    'msgFrom'   => 'From:',
    'msgTo'     => 'To:'
);
# hash wyrazen regularnych
# strunktura identyczna z %COLUMNS, ale values to wyrazenia regularne
# generowany funkcyjnie na starcie programu
# = (
#   'msgId' => {
#       '('     => qr/<&%MSGID%&>/
#       ')'     => qr/<&%DIGSM%&>/
#    }
#    ...
#    ...
# )
my %REGEXS_BRACKETS = ();

# << SZABLONY
#---------------------------------------------------------------------

#---------------------------------------------------------------------
# ZMIENNE GLOBALNE >>

# wszystkie skróty dla opcji
# skryptu (tryby)
# a(dd) -> dodawanie folderu
# s(earch) -> wyszukiwanie
my %optkeys_settings = (
'add'       => 'add=s@',
'list'      => 'list',
'search'    => 'search=s%',
'dump'      => 'dump=s',
'clear'     => 'clear',
#'title'     => 'title=s',
#'sender'    => 'sender|e=s',
);

# Hash zawierajacy opcje z jakimi
# uruchomiono skrypt
my %options = ();

# Hash zawierający wyrazenia regularne
# jakimi uzytkownik chce przeszukać
# naglowki maili

my %input_search_names = (
    'subject'   =>  'msgSub',
    'to'        =>  'msgTo',
    'from'      =>  'msgFrom',
);
my %input_regexps = ();

# ścieżka do pliku .dbm z naglowkami mail
my $MAIL_DATA_PATH = ".szmaildata.dbm";

# ścieżka do pliku .dbm z śledzonymi folderami mailowymi
my $MAIL_FOLDERS_PATH = ".szmailfolders.dbm";

# hash z którym wiązana jest BD z naglowkami maili
my %mails = ();
# obiekt klasy DB_File na DB z naglowkami maili
my $mail_obj;

# hash z którym wiązana jest BD ze śledzonymi folderami
my %folders = ();
# obiekt klasy DB_File na DB ze śledzonymi folderami
my $fold_obj;

# manager mailboxa Mail::Box::Manager
my $mail_manager;

# << ZMIENNE GLOBALNE
#---------------------------------------------------------------------


#---------------------------------------------------------------------
# FUNKCJE INICJUJĄCE >>

sub loadRegexs {
# inicjuje hash %REGEXS_BRACKETS
    foreach my $key (keys %COLUMNS) {
        $REGEXS_BRACKETS{$key}{'('} = qr/$BRACKETS{'('}$COLUMNS{$key}{'('}$BRACKETS{')'}/;
        $REGEXS_BRACKETS{$key}{')'} = qr/$BRACKETS{'('}$COLUMNS{$key}{')'}$BRACKETS{')'}/;
    }
}


sub loadDB {
# ladowanie baz danych
    $mail_obj = tie %mails, "DB_File", $MAIL_DATA_PATH, O_RDWR|O_CREAT, 0666, $DB_BTREE
        or die "Nie mozna otworzyc bazy danych $MAIL_DATA_PATH: $!\n";

    $fold_obj = tie %folders, "DB_File", $MAIL_FOLDERS_PATH, O_RDWR|O_CREAT, 0666, $DB_BTREE
        or die "Nie mozna otworzyc bazy danych $MAIL_FOLDERS_PATH: $!\n";
}

sub init_szmail {
    # binmode STDOUT, ":utf8";
    GetOptions(\%options, values %optkeys_settings);
    loadRegexs;
    loadDB;
    $mail_manager = Mail::Box::Manager->new;
}

# << FUNKCJE INICJUJĄCE
#---------------------------------------------------------------------


#---------------------------------------------------------------------
# FUNKCJE ZAMYKAJĄCE >>

sub saveDB {
# zamykanie baz danych
    undef $mail_obj;
    undef $fold_obj;

    untie %mails;
    untie %folders;
}

sub exit_szmail {
    saveDB;
    my $retcode = shift;
    exit($retcode);
}


# << FUNKCJE ZAMYKAJĄCE
#---------------------------------------------------------------------


#---------------------------------------------------------------------
# FUNKCJE HASH - STRING >>

# TODO ignoruj nieznane kolumny
sub hashToStringMailData {
# przekształc hash w zakodowany string
# argumenty :
#   %hash  -> ref. na hash z wartosciami
#   @order -> ref. na tablice z kolejnoscia haseł

    my %hash = %{shift(@_)};
    my @order = @{shift(@_)};
    my $outString = '';
    foreach my $key (@order) {
        if (! exists $hash{$key}) {next;}
        $outString = $outString
                    .$BRACKETS{'('}.$COLUMNS{$key}{'('}.$BRACKETS{')'}
                    .$hash{$key}
                    .$BRACKETS{'('}.$COLUMNS{$key}{')'}.$BRACKETS{')'};
    }
    return $outString;
}

sub stringToHashMailData {
# przekształć string w hash
# argumenty :
#   $string -> bazowy string
#   @keys   -> ref na tablice z kluczami
    my $string = shift;
    my @keys = @{shift(@_)};
    my %outHash = ();
    # my %reghash = (); TODO zaladuj regex wczesniej
    foreach my $key (@keys) {
        if (! exists($REGEXS_BRACKETS{$key})) { next; };
        if ( $string =~ m/$REGEXS_BRACKETS{$key}{'('}(.*)$REGEXS_BRACKETS{$key}{')'}/ ) {
            $outHash{$key} = $1;
        } else {
            $outHash{$key} = '';
        }
    }
    return %outHash;
}


sub hashToRegexMailData {#TODO
# przekształć hash na wyrażenie regularne.
# argumenty :
#   %hash   -> hash string -> string, gdzie kluczom (hasłom np msgFrom)
#               odpowiada wyrazenie regularna zapisane w stringu
}


sub addressArrayToString {
# przekształć tablice adresów Mail::Address
# na string (adres1@mail)(adres2@mail)...}
# argumenty :
#   @addrs  -> tablica Mail::Address
    my @addrs = @_;
    my @addrsStrings = map $_->address, @addrs;
    my $outString = join($ADDRESS_BRACKETS{')'}.$ADDRESS_BRACKETS{'('}, @addrsStrings);
    $outString = $ADDRESS_BRACKETS{'('}.$outString.$ADDRESS_BRACKETS{')'};
    return $outString;
}

# << FUNKCJE HASH - STRING
#---------------------------------------------------------------------


#---------------------------------------------------------------------
# FUNKCJE POMOCNICZE REGEXP >>

sub inputStringToRegexp {
# towrzy wyrażenie regularne ze stringa otrzymanego
# z od użytkownika
# argumenty :
#   $instr  ->  wejścowy string
    my $instr = shift;
    return qr/$instr/;
}

sub getInputRegexps {
# odczytaj regularne wyrazenia podane przez uzytkownika
# i zapisz w globalnym hashu %input_regexps

    # bez opcji szukania, nic nie rob
    return unless exists $options{'search'};

    foreach my $searchOpt (keys %{$options{'search'}}) {
        if (exists $input_search_names{$searchOpt}) {
            $input_regexps{$input_search_names{$searchOpt}} =
                inputStringToRegexp($options{'search'}{$searchOpt});
        }
        else {
            print STDERR "opcja wyszukiwania <$searchOpt> ",
                "nieobslugiwana\n";
        }
    }
}

sub procRegexpForDB {
# generuje regex do przeszukania konkretnej
# kolumny BD na podstawie podanego regex'a
# argumenty :
#   $col    -> kolumna
#   $inReg  -> wejścowy regex
    my $col = shift;
    my $inReg = shift;
    my %need_addr_brack = ('msgFrom', 1, 'msgTo', 1);
    if (exists $need_addr_brack{$col}) {
        return qr/$REGEXS_BRACKETS{$col}{'('}.*$ADDRESS_BRACKETS{'('}.*$inReg.*$ADDRESS_BRACKETS{')'}.*$REGEXS_BRACKETS{$col}{')'}/;
    }
    return qr/$REGEXS_BRACKETS{$col}{'('}.*$inReg.*$REGEXS_BRACKETS{$col}{')'}/;
}

# << FUNKCJE POMOCNICZE REGEXP
#---------------------------------------------------------------------



#---------------------------------------------------------------------
# INTERFEJS DB >>
#   |
#   |\
#   | - interfejs bazy danych nagłówków maili -> MAIL DB
#    \
#     - interfejs bazy danych śledzoncy folderów mailowych -> FOLDER DB

#   ------------------------------------------------------------------
#   * MAILD DB

sub addMailToDB {
# funkcja wstawiajaca dane naglowka maila do BD
# argumenty :
#   %mailhash   -> hash z danymi wprowadzanymi do bazy
    my %mailhash = @_;
    my $keystring = hashToStringMailData(\%mailhash, \@KEY_COLUMN);
    my $valuestring = hashToStringMailData(\%mailhash, \@VALUE_COLUMN);
    $mails{$keystring} = $valuestring;
}

sub removeMailFromDB { #TODO
# funkcja usuwajaca dane naglowka maila z BD
# argumenty :
#   %mailhash   -> hash z danymi naglowka
    my %mailhash;
}

sub clearMailsDB {
    for (keys %mails) {
        delete $mails{$_}
    }
}

#   ------------------------------------------------------------------
#   * FOLDER DB

sub addFolderToDB {
    my $folderPath = shift;
    $folders{$folderPath} = "";
    saveFolderLoadTime($folderPath);
}

sub removeFolderFromDB {
    my $folderPath = shift;
    delete $folders{$folderPath};
}

sub clearFoldersDB {
    for (keys %folders) {
        delete $folders{$_}
    }
}

sub clearDB {
    clearMailsDB;
    clearFoldersDB;
}
# << INTERFEJS DB
#---------------------------------------------------------------------

#---------------------------------------------------------------------
# INTERFEJS FOLDERÓW >>

sub saveFolderLoadTime {
    my $folderPath = shift;
    $folders{$folderPath} = time;
}

sub isFolderDirty {
    my $folderPath = shift;
    # czy mamy ten folder w bazie danych?
    # jak nie to znaczy ze jest brudny
    if (!exists($folders{$folderPath})) {
        return 1;
    }

    my $folderStats = stat($folderPath);

    # czy udalo sie odczytac dane tego pliku
    if (!$folderStats) {
        printf "Nie mozna pobrac informacji o $folderPath: $!\n";
        return -1;
    }

    my $timestamp = $folderStats->mtime;

    # czy zapamietany czas odczytu tego folderu jest
    # mniejszy niz czas ostatnie jego modyfikacji
    return ($folders{$folderPath} < $timestamp) ? 1 : 0;
}

sub getFolderToIDsHash {
# tworzy hash nazwa_folderu -> [id1, id2]
# z hasha w formacie DB
# argumenty :
#   %selected   -> hash w formacie db (jak %mails)

    my %selected = @_;
    my %foldersToIDs = ();
    my %temp = ();
    while (my ($key, $value) = each (%selected)) {
        %temp = stringToHashMailData($key.$value, ['msgId', 'folder']);
        push(@{$foldersToIDs{$temp{'folder'}}}, $temp{'msgId'});
    }
    return %foldersToIDs;
}

# << INTERFEJS FOLDEROW
#---------------------------------------------------------------------


#---------------------------------------------------------------------
# INTERFEJS MAILI >>


sub deleteMailsFromThisFolder {
# usun wszystkie zapisane naglowki w %mails
# pochodzace z folderu o nazwie $folderName
    my $folderName = shift;
    my $reg = qr/$REGEXS_BRACKETS{'folder'}{'('}$folderName$REGEXS_BRACKETS{'folder'}{')'}/;
    foreach my $keycol (keys %mails) {
        if ($mails{$keycol} =~ m/$reg/) {
            delete $mails{$keycol};
        }
    }
}

sub loadMailsFromThisFolder {
# zaladuj wszystkie naglowki maili do %mails
# pochodzace z folderu o nazwie $folderName
    my $folderName = shift;
    my %dataHash = (
        'msgId'     => '',
        'msgSub'    => '',
        "msgFrom"   => '',
        'msgTo'     => '',
        'folder'    => $folderName,
    );
    my $folder = $mail_manager->open('folder' => $folderName) or
        (print STDERR "nie mozna otworzyc folderu poczty $folderName: $!\n" and return 1);

    my $tempstr;
    foreach my $msg ($folder->messages) {
        $dataHash{'msgId'}   = $msg->messageId;
        #$dataHash{'msgSub'}  = $msg->subject;
        $tempstr = $msg->head->get('subject')->study;
        $tempstr =~ s/[^[:ascii:]]+//g;
        $dataHash{'msgSub'} = $tempstr;
        #print utf8::is_utf8($tempstr), "<><\n";
        #$dataHash{'msgSub'}  = utf8::decode($tempstr);
        #print $dataHash{'msgSub'}, "<<<<\n";
        $dataHash{'msgFrom'} = addressArrayToString($msg->sender);
        $dataHash{'msgTo'}   = addressArrayToString($msg->to);

        addMailToDB(%dataHash);
        #       foreach (keys %dataHash) {
        #print "$_ => $dataHash{$_}\n";
        #}
    }
    $mail_manager->close($folder);
    return 0;
}

sub drawListOfHeaders {
# rysuje tabelę z danymi naglowkow maili na STDOUT
# argumenty :
#   @colsIDs            -> ref. klucze kolumn w danych naglowkow maili
#   %colsNames          -> ref. nazwy dla kluczy klucz -> nazwa
#   @maildataArr        -> ref na tablece z hashami maili
    my @colsIDs = @{shift(@_)};
    my %colsNames = %{shift(@_)};
    my @maildataArr = @{shift(@_)};
    my $table = Text::Table->new(map {$colsNames{$_}} @colsIDs);
    my @line = ();
    foreach my $mail (@maildataArr) {
        @line = map{$mail->{$_} ? $mail->{$_} : ''} @colsIDs;
        $table->add(@line);
    }
    print "\n\n\tList of mail headers\n";
    print "$table\n";
}
# << INTERFEJS MAILI
#---------------------------------------------------------------------
#---------------------------------------------------------------------
# INTERFEJS UZYTKOWNIKA >>
sub displayList {
# wyświetla tabele z naglowkami mail
# argumenty :
#   %dbhash     -> hash w formacie DB (jak %maile)
    my %dbhash = @_;
    my @colsIDs  = ('nr', 'msgSub', 'msgFrom', 'msgTo');
    my %colsNames  = (
        'nr'        => 'Nr:',
        'msgSub'    => 'Subject:',
        'msgFrom'   => 'From:',
        'msgTo'     => 'To:',
    );
    my @dataArr = ();
    my $count = 1;
    foreach my $m (keys %dbhash) {
        push @dataArr, {'nr' => $count, stringToHashMailData($m, \@colsIDs)};
        $count++;
    }
    drawListOfHeaders(\@colsIDs, \%colsNames, \@dataArr);
}

sub searchHeaders {
# przeszukaj baze danych z opcjami
# podanymi przez uzytkownika

    my %selected = ();
    getInputRegexps;

    my $searchReg = '';
    my $tempReg = '';
    foreach my $key (keys %input_regexps) {
        $tempReg = procRegexpForDB($key, $input_regexps{$key});
        $searchReg = qr/(?=.*$tempReg)$searchReg/;
    }
    while ( my ($hash, $value) = each (%mails)) {
        if($hash =~ $searchReg) {
            $selected{$hash} = $value;
        }
    }
    return %selected;
}

sub copyMailsToFolder {
# przenies maile o danych nagłówkach
# do folderu
# argumenty :
#   $folderName     -> nazwa folderu docelowego
#   %selected       -> hash w formie db z mailami do kopiowania

    my $folderName = shift;
    my %selected = %{shift(@_)};

    # otwórz folder docelowy managerem
    my $destFolder = $mail_manager->open('folder' => $folderName, 'create' => 1, 'access' => 'w') or
        print STDERR "Nie udalo sie otworzyc folderu docelowego $folderName: $!\n" and return;

    my %foldersToIDs = getFolderToIDsHash(%selected);

    my $mailFolder;
    my $message;
    foreach my $foldPath (keys %foldersToIDs) {
        # sprobuj otworzyc folder
        $mailFolder = $mail_manager->open('folder' => $foldPath) or
            print STDERR "Nie udalo sie otworzyc folderu z mailami $foldPath: $!\n" and next;

        foreach my $msgid (@{$foldersToIDs{$foldPath}}) {
            $message = $mailFolder->messageId($msgid) or
                print STDERR "Nie udalo sie znaleźć wiadomości\n",
                    "ID: $msgid\n w folderze $foldPath: $!\n" and next;

            $mail_manager->copyMessage($destFolder, $message);
        }
        $mail_manager->close($mailFolder);
    }
    $mail_manager->close($destFolder);
}

sub loadFolder {
# ładuje maile z tego folderu do bazy danych
# argumenty :
#   $folderPath     -> sciezka do folderu

    my $folderPath = shift;
    if (isFolderDirty($folderPath)) {
        #TODO jakoś lepiej?
        if (exists $folders{$folderPath}) {
            deleteMailsFromThisFolder($folderPath);
        }
        if(loadMailsFromThisFolder($folderPath) == 0) {
            addFolderToDB($folderPath);
            print "Pomyślnie zaladowano maile z folderu $folderPath\n";
        } else {
            print "Nie udało się załadować maili z folderu $folderPath: $!\n";
        }
    } else {
        print "Folder $folderPath niezmieniony od ostatniego ładowania\n";
    }
}

# << INTERFEJS UZYTKOWNIKA
#---------------------------------------------------------------------



# MAIN

init_szmail;
if (exists $options{'add'}) {
    foreach my $addFolder (@{$options{'add'}}) {
        loadFolder($addFolder);
    }
}
if (exists $options{'search'}) {
    my %selected = searchHeaders;
    displayList(%selected);
    if(exists $options{'dump'}) {
        copyMailsToFolder($options{'dump'}, \%selected);
    }
} elsif (exists $options{'list'}) {
    displayList(%mails);
} elsif (exists $options{'clear'}) {
    print "Czyszczenie BD\n";
    clearDB;
}
exit_szmail(0);

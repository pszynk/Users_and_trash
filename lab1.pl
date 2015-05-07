#!/usr/bin/perl
use strict;
use warnings;
use DB_File;
use Fcntl;
use Getopt::Std;
use feature "switch";

my $confFile;
my $confFilePath = './config';
my $dbFileName = 'baza.dbm';
my $MAGIC_NUM = "_32_";
my $msgFrom, my $msgTo, my $msgSubject, my $msgId;
my @mailFolders;
my @foundMsgs;
my %mailHash;
my %opts;

sub loadDB {
	tie (%mailHash, 'DB_File', $dbFileName,  O_CREAT|O_RDWR, 0644) or
		die "Can't open or create database \n";
}

sub saveDB {
	untie %mailHash;
}

sub loadConf {
	open($confFile, '<', $confFilePath ) or die 'Can\'t load a config file: $!';
	
}
sub getMailFolders {
	 while(<$confFile>) {
		 chomp;
		 push @mailFolders, $_;
	 }
}
sub scanMailFolder {
	my $tmpFolder;
	my $tmpConcat;
	my $msgLine;
	my $msgNext=1;
	my $FolderName;
	my $Line;
	foreach (@mailFolders) {
		open $tmpFolder, '<', $_ or (print "Can't open folder $_\n" and next);
		$FolderName = $_;
		$msgLine = 0;
		#print;
		while (<$tmpFolder>) {
			$msgLine++;
			if($msgNext) {
				next if !(/^From\s/);
			}
			if($msgNext == 1) {
				$msgNext =0;
				$Line = $msgLine;
				}
			chomp;
			if($_ ne "") {
				given($_) {
					when (/^From:/) {
						s/From://;
						s/\s//;
						chomp;
						$msgFrom = $_;
					}
					when (/^Subject:/) {
						
						s/Subject://;
						chomp;
						$msgSubject = $_;
					}
					when (/^To:/) {
						s/To://;
						s/\s//;
						chomp;
						$msgTo = $_;
					}
					when (/^Message-ID:/) {
						s/^Message-ID://;
						chomp;
						$msgId = $_;
					}
						
				}	
			}
			else {
				$msgNext = 1;
				$tmpConcat = "${msgId}${MAGIC_NUM}${msgFrom}${MAGIC_NUM}${msgTo}${MAGIC_NUM}${msgSubject}";
				$mailHash{$tmpConcat} = "${FolderName}${MAGIC_NUM}${Line}";
			}			
		}
			
			
	} 
	close $tmpFolder;
}

sub display {
	my $Hash;
	my @tmp;
	my ($FolderName,$msgLine);
	my $i = 0;
	my $ans;
	my $usrPath;
	my $usrFile, my $scrFile, my $tmpLine, my %mem;
	if(@foundMsgs > 0) {
		print "Found ".($#foundMsgs + 1)." message(s)\n";
		print "Would you like to see headers y/n\n";
		$ans=<>;
		chomp $ans;
		if($ans eq 'y') {
			for($i=0; $i < @foundMsgs; $i++ ) { 
				$Hash = $foundMsgs[$i];
				#print $Hash;
				@tmp = split(/$MAGIC_NUM/, $mailHash{$Hash});
				$FolderName = $tmp[0];
				$msgLine = $tmp[1];
				print "Message: ".($i+1)."\n";
				print "Folder name: ${FolderName}  Line number: ${msgLine} \n";
				@tmp = split(/$MAGIC_NUM/,$Hash);
				print "From: ${tmp[1]}\n";
				print "To: ${tmp[2]}\n";
				print "Subject: ${tmp[3]}\n";
				print "--------------\n";
				
			}
			
		}
		print "Would you like to copy them to another folder\n";
		$ans=<>;
		chomp $ans;
		if($ans eq 'y') {
			print "Please give a path to new mail folder with path \n";
			$usrPath = <>;
			chomp $usrPath;
			open($usrFile, '>', $usrPath ) or die "Can't make file: $!"; 
			foreach(@mailFolders) {
				open $scrFile, '<', $_ or (print "Can't open folder $_\n" and next);
				$mem{$_} =  \$scrFile;
			}
			for($i=0; $i < @foundMsgs; $i++ ) { 
				$Hash = $foundMsgs[$i];
				#print $Hash;
				@tmp = split(/$MAGIC_NUM/, $mailHash{$Hash});
				$FolderName = $tmp[0];
				$msgLine = $tmp[1];
				open($scrFile, '<', $FolderName ) or die "Can't read file: ${FolderName} $!"; 
					
				close $scrFile;
				 
				
			}
			
			close $usrFile;
		}
		
	}
	else{
		print "No messages found";
	}
	
}

sub regSearch {
	my ($searchReg, $hash);
	$searchReg = shift;
	for   $hash (keys %mailHash) {
		if ($hash =~ /$searchReg/) {
			push @foundMsgs, $hash
		}
	}
	display();
	
}


getopts("ur:", \%opts);
loadConf();
getMailFolders();
loadDB();
if($opts{"u"}) {
	scanMailFolder();
}
if($opts{"r"}) {
	regSearch($opts{"r"});
}




close $confFile;
saveDB();

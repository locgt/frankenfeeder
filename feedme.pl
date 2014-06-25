#!/usr/bin/perl
################
## feedme.pl
## Watches a gmail account for a feed command
## then executes the command returning results to sender.
## For use with a frankenfeeder: http://locgt.blogspot.com/2013/08/frankenfeeder-part-i.html
## 1-11-13 - @vmfoo 
##
## LOTS borrowed from examples for the reciever/sender perl modules. 
##
## for raspbian, debian, or ubuntu, install the following libraries to get proper modules
## sudo apt-get install libnet-imap-simple-ssl-perl libio-socket-ssl-perl libemail-simple-perl sendemail streamer
##
## if sendemail complains about the wrong SSL version, make your own copy of it and edit line  1907: 'SSLv3 TLSv1' => 'SSLv3'
## then fix the EmailReply funciton to call your fixed version.
## see: http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=679911
##
## also need to set: /etc/sysctl.conf vm.overcommit_memory=1
## if streamer throws a connot allocate memory error. see: http://home.nouwen.name/RaspberryPi/webcam.html

use strict;
use warnings;

# required modules
use Net::IMAP::Simple;
use Email::Simple;
use IO::Socket::SSL;

# fill in your details here
my $username = 'YOURACCOUNTHERE@gmail.com';
my $password = 'YOURGMAILPASSWORD';
my $mailhost = 'pop.gmail.com';
my $pinA = 17;  #What pins are the wires connected to?
my $pinB = 22;

#also edit the SECRETFEEDCOMMAND and SECRETTAKEPICCOMMAND placeholders below to set your own
#subjects that will trigger the feed/pic or pic commands.  

my $logname="/tmp/feedme.log";
my $picname="/tmp/dogpic.jpeg";
my $erroremail = 'WHERETOSENDERROREMAILS@gmail.com';
my $sendemail = '/home/pi/scripts/feedme/sendemail';  #which sendemail script to use

my $writelog = 0; #only write out to sdcard log during setup or if you need it
		  #or you will burn a whole in your card

##Function Prototypes
sub feedme();
sub takepic();


#flags for commands
my $feedme = 0;
my $takepic = 0;
my $from ="";  #who to reply to when receiving feedme command

Log("--------------------------");
Log("Checking $username mailbox for new commands");
# Connect
my $imap = Net::IMAP::Simple->new(
    $mailhost,
    port    => 993,
    use_ssl => 1,
) || ErrorHandler("Unable to connect to IMAP: $Net::IMAP::Simple::errstr");

# Log in
if ( !$imap->login( $username, $password ) ) {
    ErrorHandler("Login failed: " . $imap->errstr);
#    exit(64);
}
# Look in the the INBOX
my $nm = $imap->select('INBOX');

# How many messages are there?
my ($unseen, $recent, $num_messages) = $imap->status();
Log("Status: unseen: $unseen, recent: $recent, total: $num_messages");

#get the list of unseen messages
my @unseen = $imap->search("UNSEEN");
if (! scalar( @unseen) ) {
#no messages
	Log( "No new messages.  Exiting.");
	$imap->quit;
	exit;	
}

## Iterate through unseen messages
foreach my $i (@unseen){
    my $es = Email::Simple->new( join '', @{ $imap->top($i) } );
    Log(sprintf( "[%03d] From: %s Subject: %s", $i, $es->header('From'), $es->header('Subject') ) );
    $from=$es->header('From');
    if ( $es->header('Subject') =~ /SECRETFEEDCOMMAND/ ) {  #change this to the subject that will trigger a feed
    	Log("Feed me command message found from $from");
    	$feedme++;
    	$imap->see($i);
    }
    if ( $es->header('Subject') =~ /SECRETTAKEPICCOMMAND/ ) { #change this to the subject that will trigger a pic
    	Log("pic command found from $from\n");
    	$takepic++;
	   	$imap->see($i);
    }
}

## Perform commands
if ($feedme > 0) {
		feedme();
}

Log("Feedme check complete.  Exiting.");
# Disconnect
$imap->quit;

exit;


sub feedme(){
	#Do the feeding function
	Log("Executing feedme function for $from.");
	#perform system calls to activate feeder
	my $sleep=65;  #how long to sleep and let a rotation complete

	#feed dogs with 8 rotations (enough for two dogs)
	dumpfood();
	sleep $sleep;
	dumpfood();
	sleep $sleep;
	dumpfood();
        sleep $sleep;
	dumpfood();
        sleep $sleep;
	dumpfood();
        sleep $sleep;
	dumpfood();
        sleep $sleep;
	dumpfood();
        sleep $sleep;
	dumpfood();

	
	#reply that the feeder was activated to $from
	Log("Feeder succesfully activated at: ".now());
	
	#sleep a few and then take a picture of the dogs
	takepic();
	Log("Picture taken.  Sending email.");
	EmailReply($from, "Feeder succesfully activated at: ".now(), $picname);
	#clean up picture
	unlink $picname;

}

sub dumpfood(){
	Log("Dumping food once.");
	#do wiringPi command to activate feeder pins
        `/usr/local/bin/gpio -g mode $pinA out`; #ensure the pin is in correct mode
        `/usr/local/bin/gpio -g mode $pinB out`; #ensure the pin is in correct mode
        `/usr/local/bin/gpio -g write $pinA 1`;
        `/usr/local/bin/gpio -g write $pinB 1`;
        sleep 1; #press buttons for 1 second
        #do wiringPi command to deactivate feeder pins
        `/usr/local/bin/gpio -g write $pinA 0`;
        `/usr/local/bin/gpio -g write $pinB 0`;
	Log("Food Dumped.");
} 

sub takepic(){
	#Do the picture function
	Log("Executing takepic function for $from.");
	`/usr/bin/streamer -o \"$picname\"`;
}

sub Log {
	my ($message) = shift;
	#print now().":  $message\n";
	if ($writelog > 0) {
		open (OUT, ">>$logname");
		print OUT now().":  $message\n";
		close OUT;
	}
}

sub now{
	my ($logsec,$logmin,$loghour,$logmday,$logmon,$logyear,$logwday,$logyday,$logisdst)=localtime(time);
	my $logtimestamp = sprintf("%02d-%02d-%4d %02d:%02d:%02d",$logmon+1,$logmday,$logyear+1900,$loghour,$logmin,$logsec);
	return $logtimestamp;
}

sub ErrorHandler {
	my ($message) = shift;
	Log("Feedme Critical Error encountrered: $!.  Alerting.");
	Log ("Error: $message");
	alertOnError($message, $!);
	exit;
}

sub alertOnError {
	my ($message, $error)=@_;
	EmailReply("DogFeederAlert: $message, $error");
	
}

sub EmailReply{
	my ($to,$message, $file) = @_;
	Log("Sending message to: $to.");
	my $now=now();
	
	my $command ="$sendemail -f $username -t \"$to\" -u \"Re: feedme\" -m \"They have been fed at: $now\" -s smtp.gmail.com:587 -o tls=yes -o username=\"$username\" -o password=\"$password\"";
	if ($file) {
		if (-e $file ) {
		 $command.=" -a $file";		
		}	else {
			Log("Error finding $file.  Webcam broken?");
		}
	}
	#print "$command\n";
	my $results;
	$results=`$command`;
	chomp $results;
	Log("Send results: $results");
}

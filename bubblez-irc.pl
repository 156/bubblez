#!/usr/bin/perl

#
# bubblez irc bot <3
#

use Getopt::Std;

use POE;
use POE::Component::IRC;

use AI::MegaHAL;

getopts('n:r:i:s:p:c:h');

my @responses = ("hey:text:test");

my $VERSION = '0.1';
my $NAME = 'Bubblez';

my $irc;
my $megahal;

my $brainsave = 1;
my $brainpath = './';

# irc stuff
my $nickname;
my $realname;
my $ircname;
my $server;
my $port;
my @channels;
my $channels;

$nickname = $opt_n;
$realname = $opt_r;
$ircname = $opt_i;
$server = $opt_s;
$port = $opt_p;
$channels = $opt_c;

$nickname |= ($NAME . $$ );
$realname |= $NAME . " " . $VERSION;
$ircname |= $NAME . " " . $VERSION;
$server |= "irc.theinfinitynetwork.org";
$port |= 6667;
$channels |= "#infn";

@channels = split(/ /, $channels);

# megahal
$megahal = AI::MegaHAL->new('Path' => $brainpath, 'Prompt' => 0, 'Wrap' => 0, 'AutoSave' => $brainsave);

#irc
$irc = POE::Component::IRC->spawn();

# create poe session
POE::Session->create(
  inline_states => {
    _start     => \&bot_start,
    irc_001    => \&on_connect,
    irc_public => \&on_public,
    irc_disconnected => \&tryreconnect,
    irc_error        => \&tryreconnect,
    irc_socketerr    => \&tryreconnect,
    autoping         => \&doping,

  },
);

sub bot_start
{
  $irc->yield(register => "all");

  $irc->yield(
    connect => {
      Nick     => $nickname,
      Username => $realname,
      Ircname  => $ircname,
      Server   => $server,
      Port     => $port,
    }
  );
}

sub on_connect {  foreach (@channels) { $irc->yield('join', $_ ); } }

sub doping
{
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];

    $kernel->post( bot => userhost => $config->{nickname} )unless $heap->{seen_traffic};
    $heap->{seen_traffic} = 0;
    $kernel->delay( autoping => 300 );
}

sub tryreconnect
{

    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];

    $kernel->delay( autoping => undef );
    $kernel->delay( connect  => 15 );
}

sub on_public
{
  my ($kernel, $who, $where, $msg) = @_[KERNEL, ARG0, ARG1, ARG2];
  my $nick    = (split /!/, $who)[0];
  my $channel = $where->[0];
  my $ts      = scalar localtime;
  
  my $hadnick = 0;
  
  if ($msg =~ /$nickname/) { $msg =~ s/$nickname //g; $msg =~ s/$nickname//g; $hadnick = 1; }

  if ($msg =~ /^\.loadresponses/) { @responses = (); open FD, "brain.txt"; while (<FD>) { chomp; push @responses, $_; } close FD; }
  if ($msg =~ /^\.saveresponses/) { open FD, ">brain.txt"; foreach my $r (@responses) { print FD "$r\n"; } close (FD); }
  
  if (my ($msgstring) = $msg =~ /^\.addresponse (.*)/) { push @responses, $msgstring; return; }

  if ($msg =~ /time/) { $irc->yield(privmsg =>$channel, `date`); return; }
  if ($msg =~ /date/) { $irc->yield(privmsg =>$channel, `date`); return; }
  
  my @output = ();
  my $doresponse = 0;

  # must be language
  
  $megahal->learn($msg);
  
  AI::MegaHAL::megahal_cleanup();
  
  if ($hadnick)
  {
  foreach my $response (@responses)
  {
   # my ($m, $f, $v) = split(/:/, $response);
    if ($response =~ /(\S+)\:(\S+)\:(.*)/)
    {
      my $m=$1;
      my $f=$2;
      my $v=$3;
      
      if ($msg =~ /$m/) {
        if ($f eq "text")
        {
          push @output, $v;
          $doresponse=1;
        }
         if ($f eq "markov")
        {
          push @output, $megahal->do_reply($v);
          $doresponse=1;
        }
      }
    }
  }
  
  if ($doresponse)
  {
    $irc->yield(privmsg => $channel, $output[rand @output]);
    return;
  }
  
  # everything else has failed
  $irc->yield(privmsg => $channel, $megahal->do_reply($msg));
  
  }
}

$poe_kernel->run();

exit 0;
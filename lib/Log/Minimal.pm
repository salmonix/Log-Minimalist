package Log::Minimal;
our $VERSION=20150330;

use 5.010;
use warnings;
use strict;

use Method::Signatures; # I'll remove it
use Data::Dumper;
$Data::Dumper::Sortkeys=1;

use Term::ANSIColor qw(colored);
use IO::Interactive qw(is_interactive);
use Carp qw( confess longmess croak carp );
use Scalar::Util qw(weaken);
use Memoize;
use File::Spec;

use POSIX qw(strftime);
my $Date = strftime("%F_%H",localtime);

our $LOGPATH = $ENV{PWD};
our $LOGFILE = join('_', $0,$Date, "$$.log.gz");
our $LOGLEVEL = 'notice';

our %Levels = (
    'debug' => [6,'bold white'],
    'info' => [5,'cyan'],
    'notice' =>[4, 'bold green'],
    'warning' => [3,'bold yellow'],
    'error' => [2,'bold red'],
    'critical' => [1,'bold red'],
);

local $Carp::RefArgFormatter = sub { Dumper $_[0] };
our @CARP_NOT = (__PACKAGE__);

my %Handlercache;
my $Start = time;

my $Skelet = [];
map { $Skelet->[ $Levels{$_}->[0] ] = sub { 1 } } keys %Levels; # pos 0 is the loglevel
my $Cache = $#$Skelet+1;

memoize('new');
method new( :$loglevel='notice', :$screen=0, :$logfile, :$logpath=$LOGPATH, :$cache, :$code ) {
    $self = [];
    @$self = @$Skelet;
    bless $self,__PACKAGE__;

    $loglevel = lc $loglevel;
    if ( $0 =~ /-/ ) { $loglevel ||= 'silent' }; # no log when one-liner

    my $levels = join('|', keys %Levels );
    if ( $loglevel !~ $levels ) { croak "Unknown loglevel is defined." };

    $self->[0] = $loglevel;
    if ( $self->[0] eq 'silent' ) {
        $self->[0] = 0;
        return $self;
    }

    my %handlers;
    $handlers{'cache'} = $cache;
    $handlers{'code'} = $code;

    if ( is_interactive ) {
        $handlers{'screen'} = 1;
        if ( $0 =~ /.*t$|-/ ) {  # no logfile for test and one liner unless wanted
            if ( !$logfile ) { return $self->build( \%handlers ); }
        }
    } else {
        $logfile ||=$LOGFILE;
        $handlers{'logfile'} = $self->get_filehandler($logfile, $logpath);
    }

    return $self->build( \%handlers );
}


sub debug    { $_[0]->[6]->( @_ ) };
sub info     { $_[0]->[5]->( @_ ) };
sub notice   { $_[0]->[4]->( @_ ) };
sub warning  { $_[0]->[3]->( @_ ) };
sub error    { do {$_[0]->[2]->( @_ ); carp; return 1}; };  # TODO checkit
sub critical { do {$_[0]->[1]->( @_ ); confess;} };  # TODO checkit

method build( $handlers ) {

    my @levels = sort { $Levels{$a}->[0] <=> $Levels{$b}->[0] } keys %Levels;
    my $max_level =  $Levels{ $self->[0] }[0];

    for my $level_name ( @levels  )  {
        my $loglevel = $Levels{$level_name}->[0];
        last if $loglevel > $max_level;
        $self->[$loglevel] = add_logcode($loglevel, $level_name, $handlers );
    }

    $self->[0] = $max_level;
    return $self;
}

func add_logcode($loglevel, $level_name, $handlers) {

        my $level_pretty = sprintf('% -7s',$level_name);
        my $code =<<CODE
my \$elapsed = time - $Start;
my \$self = shift;
my \$message = sprintf( "\@_" );
\$message = sprintf(\"[% 6d] $level_pretty %s\", \$elapsed, \$message);

CODE
;

        # put into the handlers. Add stack handler.
        if ( $handlers->{'screen'} ) {
            my $color = $Levels{$level_name}->[1];
            $code .= " say STDERR colored(\$message,'$color');\n";
        }
        if ( $handlers->{'logfile'} ) {
            $code .=  "say \$logfile \$message;\n"
        }
        if ( $handlers->{'cache'} ) {
            $code .= "push \@{ \$self->[$Cache]},\$message;\n";
        }

        my $codesarray;
        my $coderef;
        if ( $handlers->{'code'} ) {
            if ( ref $handlers->{'code'} eq 'ARRAY' ) {
                my @snipps = map {
                    if ( ref $handlers->{'code'}[$_] eq 'CODE') {
                        "\$codesarray->[$_](\@_)";
                    } else {
                        croak "${$_}th element in 'code' ARRAY parameter is not CODE ref, but ".$handlers->{'code'}[$_];
                    }
                } 0..$#{$handlers->{'code'}};
                $code .= join("\n", @snipps );
                $codesarray = $handlers->{'code'};
            } else {
                $coderef = $handlers->{'code'};
                $code .="\$coderef->(\@_);\n"
            }
        }

        my $b = sub {
            my $logfile = $handlers->{'logfile'};
            return eval 'sub{'.$code.'};'
        };
        return $b->();
}


# TODO: Add docu and test
sub get_cache { say Dumper $_[0]; return $_[0]->[$Cache] };
sub clear_cache { return delete $_[0]->[$Cache] };

method get_filehandler($logfile, $logpath) {

    $logfile = File::Spec->catfile($logfile,$logpath);

    if ( !ref $logfile ) { # that is not a fh. Maybe closed
            my $file;
            if ( $logfile =~ /\.gz$/ ) {
                open( $file, "| gzip --best -c >> $logfile" ) or die $!;
            } else {
                open( $file, '>>',$logfile ) or die $!;
            }
            $logfile = $file;
    }
    return $logfile;
}

1;

__END__
=head1 NAME Log::Minimal

 Simple and fast OO logger for simple purposes.

=head1 SYNOPSIS

 use Log::Minimal;
 $Log::Minimal::LOGPATH='/var/log/mylogs/'; # optional

 # to receive a process.pl_YYYY-MM-DD_HH:MM:SS_PID.log.gz logging instance
 # that also logs to screen
 my $log = Log::Minimal->new();

 $log->notice("It is a notice.");


 sub foo {
    my $log = Log::Minimal->new( loglevel=>'debug' ); # an instance with debug level
    $log->dump("Bug here: ", $data );
 }

 my $dbh->prepare('INSERT INTO logs(message, parameters ) VALUES (?,?)');
 my $code = sub {
     my ( $message, @params ) = @_;
     $dbh->execute($message, join(',',@params);
 };

 my $log = Log::Minimal->new( loglevel=>'notice',code=>$code );

=head1 DESCRIPTION

=over

=item Use case

 The logger offers limited configurability and focuses on the use-cases
 that seem to be generic enough to satisfy a good number of simple needs.
 These are basically logging to a file, to the screen for debugging,
 and screen-only logging when a 'one-liner' usage or testing is detected.
 It also offers a 'cache' to pile up the log messages and retrieve them
 later.

 The constructor also accepts a CODE-ref, that may contain arbitrary connections,
 eg. database, socket, etc. The CODE-ref is called with the message that
 the actual loglevel receives ( @_ ).


=item Configure and call

 The configurability is mainly done by setting package variables - as
 usually we set up a logger at the beginning of the process once - or
 via the constructor.

 Unless specified otherwise, the logger does not log when one-liner
 or test script is detected as 'main'.

 The logger can be called with different loglevel parameters offering a
 flexibility to set different logging for different pieces of the code.
 That can be handful when debugging.

 The logger offers the following loglevels:

 debug, info, notice, warning, error, critical, silent
   6      5     4       3       2       1         0

 On 'error' the callstack is dumped, but the code does not exit. This leaves
 the possibility to print error but letting the error to be handled without
 Try::Catch block. On critical the code 'croaks'. That matches the implicite
 semantic of errors that can be handled - eg. missing file -, and errors that
 can not be handled ( 'critical' ).
 The 'error' method returns 'true', thus such constructs are possible:

 my ( $val, $err ) = my_function($param);
 if ( $err ) { .... };

 while in my_function():

 if ( $wrong ) { return undef, $log->error("Error happened.") };
 return $value;

=item Logging

 Unless specified, the logfile is composed as

 Process_name_ISO-date_time_PID.log.gz

 using gzip.

 The logline format is:

 1.st line: [ date_time ] notice   PATH_TO_LOGFILE
 after:     [  elapsed  ] loglevel MESSAGE

 The decision on using elapsed seconds in the loglines instead of timestamp
 comes from the impression that a timestamp has less use compared to
 the elapsed time since start when analysing a logfile.

=back

=head2 Constructor

=over

=item - Log::Minimal->new( :$loglevel='notice', :$screen?, :$logfile, :$logpath='.' );

The constructor can take the following named parameters:

loglevel : 'name' or number || $Log::Minimal::LOGLEVEL
screen   : bool
logfile  : logfile || $Log::Minimal::LOGFILE
logpath  : path || $Log::Minimal::LOGPATH
code     : CODEREF || [ CODEREF1, CODEREF2... CODEREFn ]

=back

=head3 Variables

 The default valuse can be changed setting global variables.

=over

=item $Log::Minimal::LOGPATH = $ENV{PWD};

 The logpath. Likely this variable is the most important.

=item $Log::Minimal::COLORS

 TODO
 The colors for the screen, as per Term::ANSIColor.

 Defaults are:
 $COLORS = {
    'debug' => ['bold white'],
    'info' => ['cyan'],
    'notice' => ['bold green'],
    'warning' => ['bold yellow'],
    'error' => ['bold red'],
 };

=back

=head1 TODO

 Implement a 'dump' method.

=head1 COPYRIGHT

(c) GPL v3., 03/27/2015, Laszlo Forro

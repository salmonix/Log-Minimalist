package Log::Minimal;
our $VERSION=20150330;

use 5.010;
use warnings;
use strict;

use Data::Dumper;
$Data::Dumper::Sortkeys=1;

use Term::ANSIColor qw(colored);
use IO::Interactive qw(is_interactive);
use Carp qw( confess longmess croak carp );
use Scalar::Util qw(weaken);
use Memoize;
use File::Spec;
use File::Basename;

use POSIX qw(strftime);
my $Date = strftime("%F_%H",localtime);

our %Defaults = (
    logpath => $ENV{PWD},
    logfile => join('_', $0,$Date, "$$.log.gz"),
    loglevel => 'notice',
)

our %Levels = (
    'debug' => [6,'bold white'],
    'info' => [5,'cyan'],
    'notice' =>[4, 'bold green'],
    'warning' => [3,'bold yellow'],
    'error' => [2,'bold red'],
    'critical' => [1,'bold red'],
    'silent'   => [0],
);
my $Counter = 0;

local $Carp::RefArgFormatter = sub { Dumper $_[0] };
our @CARP_NOT = (__PACKAGE__);

my %Handlercache;
my $Start = time;

memoize('new', 'get_filehandler');

sub new {
    my ($self,%params ) = @_;
    # evaluate parameters
    if ( $params{loglevel} ){
        # check loglevel
        $loglevel = lc $params{loglevel};
        if ( $0 =~ /-/ ) { $loglevel ||= 'silent' }; # no log when one-liner
        my $levels = join('|', keys %Levels );
        if ( $loglevel !~ $levels ) { croak "Unknown loglevel is defined." };
        $params{loglevel}=loglevel;
    } else {
        $params{loglevel} = $Defaults{loglevel};
    };

    if ( delete $params{'file_defaults'} ){
        $params{logfile}||=$Defaults{logfile};
        $params{logpath}||=$Defaults{loglevel};
        $params{logfile} = File::Spec->catfile( delete $params{logpath},$params{logfile});
    }

    $self = [];
    bless $self,__PACKAGE__;


    my %handlers;
    $handlers{'cache'} = delete $params{'cache'};
    $handlers{'code'} = delete $params{'code'};

    if ( is_interactive ) {
        $handlers{'screen'} = 1;
        if ( $0 =~ /.*t$|-/ ) {  # no logfile for test and one liner unless wanted
            if ( !$params{'logfile'} ) { return $self->build( \%handlers, \%params ); }
        }
    } else {
        $handlers{'logfile'} = $self->get_filehandler($params{'logfile'});
    }

    return $self->build( \%handlers,\%params );
}


sub build {
    my ($self, $handlers, $params ) = @_;

    my @levels = sort { $Levels{$a}->[0] <=> $Levels{$b}->[0] } keys %Levels;
    my $max_level =  $Levels{ $self->[0] }[0];

    for my $level_name ( @levels  )  {
        my $loglevel = $Levels{$level_name}->[0];
        if ( $loglevel > $max_level ) {
            $self->[$loglevel] = 'dummy';
        } else {
            $self->[$loglevel] = add_logcode($loglevel, $level_name, $handlers );
        }
    }
    $self->finish_code();
}


sub finish_code {
    my ($self) = @_;
    no strict 'refs';
    $Counter++;
    my $PACKAGE = __PACKAGE__;
    $PACKAGE .= "::$$::$Counter";

    my @levels = sort { $Levels{$a}->[0] <=> $Levels{$b}->[0] } keys %Levels;
    shift @$self;
    for ( @$self ) {
        my $method = shift @levels;
        $method = "${PACKAGE}::$method";
        if ( ref $_ eq 'CODE') {
            *{$method} = $_->();
        } else {
            *{$method} = sub { return };
        }
    }

    # TODO: cache
    *{"${PACKAGE}::get_cache"}  = sub{ return $_[0]->[0] };
    *{"${PACKAGE}::clear_cache"} = sub{ $_[0]->[0] = []  };

    return bless [],$PACKAGE;
}


sub add_logcode {
    my ($loglevel, $level_name, $handlers) = @_;
    my $level_pretty = sprintf('% -7s',$level_name);
    my $code =<<CODE
my \$elapsed = time - $Start;
my \$message = sprintf( "\@[1..\$#_]" );
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
        $code .= "push \@{\$_->[0]},\$message;\n";
    }

    my $codesarray;
    my $coderef;
    if ( $handlers->{'code'} or $handlers->{$loglevel} ) {
        # here we must make them flat
        # put this whole builder into a separate function
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
            $code .="\$coderef->(\@_);\n"; # add here time - $Start
                                           # when CODE is the only handler assign it directly
        }
    }

    return sub {
        my $logfile = $handlers->{'logfile'};
        return eval 'sub{'.$code.'};'
    };
}


# make it to return either string or CODE
# if the code is the only one then we need only a code
sub add_coderef {
    my $codes = @_;
    # here we must make them flat
    # put this whole builder into a separate function
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
        $code .="\$coderef->(\@_);\n"; # add here time - $Start
                                       # when CODE is the only handler assign it directly
    }

    return $code;
}

sub get_filehandler{
    my ($logfile) = @_;

    return $Handlercache{$logfile} if $Handlercache{$logfile};
    my $fh;
    for ( $logfile ) {

        if ( /\.xz$/ ) {
            # xz : --no-sparse -9 ?
            open( $fh, "| xz -no-sparse -9 > ".$logfile ) or die $!;
            return $fh;
        }
        if ( /\.log$/) {
            open( $fh, '>>',$logfile ) or die $!;
        }
    }

    $Handlercache{$logfile} = weaken $fh;
    return $fh;
}

sub set_defaults {
    my ( $class, %defaults ) = @_;
    %Defaults = %defaults;
}

1;

__END__
=head1 NAME Log::Minimal

 Simple and fast logger for simple purposes.

=head1 SYNOPSIS

 use Log::Minimal;

 # do it once, at the beginning of the process
 Log::Minimal->set_defaults( file_defaults=>1, logpath=>'/my/tested/logpath/' );
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
 eg. database, socket, etc. The CODE-ref is called with the @_, where the first
 object is the logger instance, the rest are the parameters passed.


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
 the possibility to  handle error without Try::Catch block.  On 'critical'
 the code 'croaks'.
 That matches the implicite semantic of errors that can be handled
 - eg. missing file -, and errors that can not be handled ( 'critical' ).
 The 'error' method returns 'true', thus such constructs are possible:

 my ( $val, $err ) = my_function($param);
 if ( $err ) { .... };

 while in my_function():

 if ( $wrong ) { return undef, $log->error("Error happened.") };
 return $value;

=item Log format

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
screen   : BOOL*
screen-only : BOOL*
logfile  : logfile
logpath  : path

code     : CODEREF || [ CODEREF1, CODEREF2... CODEREFn ]
'loglevel' : CODEREF || [ CODEREF1, CODEREF2... CODEREFn ]

When a 'loglevel' is a parameter, the CODEREF value of that parameter is
added to the logging of the given loglevel. A likely use-case is sending
a message to a socket/queue/db on error/critical events in addition to
logging to the standard channels, eg. file.

Unless specified otherwise
- when interactive terminal is detected, it logs to stdout
- when main script is .t ( testfile ) logs to screen only

=back

=head3 Initiating the class

 The class method 'set_defaults' sets the default parameters, that are to be set
 automatically at every ->new() method call.
 If a set of parameters should be excluded from a given instance,
 give them a value =>'ignore' in the constructor of the instance.
 The defaults are the following:

 logpath  : `pwd`
 logfile  : 'Process_name_ISO-date_time_PID.log.xz'
 loglevel : notice

 The logfile is piped into xz. Do not forget to reinstantiate the logger in forks,
 otherwise you may get a mess. TODO : check this behaviour

=over

=head3 Levels

 The loglevels are defined in the %Log::Minimal::Levels variable.
It sets the loglevel name, severity and coloring when printing
to the screen. The colors are as per Term::ANSIColor.

our %Levels = (
    'debug' => [6,'bold white'],
    'info' => [5,'cyan'],
    'notice' =>[4, 'bold green'],
    'warning' => [3,'bold yellow'],
    'error' => [2,'bold red'],
    'critical' => [1,'bold red'],
    'silent'   => [0],
);

=back

=head1 Raison d'être

There are other log packages around.

- Log::Dispatch: multi-purpose, slow. To create a simple logger needs
                 much boilerplate. And maybe a part of that boilerplate
                 is already in Your code.
- Log::Fast: nice, simple and fast, but only with built-in socket and file support.
- Syslog::Fast: only through socket

=head1 NOTE

The Logger creates a new class for each new call and the call is 'memoized'.
The generated class is Log::Minimal::$$::[1....n];
No subclassing is supported.

=head1 TODO

 Implement a 'dump' method.

=head1 COPYRIGHT

(c) GPL v3., 03/27/2015, Laszlo Forro

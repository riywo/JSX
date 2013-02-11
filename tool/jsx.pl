#!/usr/bin/env perl
# JSX compiler wrapper working on POSIX compatible environment

use strict;
use warnings;
use warnings FATAL => 'uninitialized';

package App::jsx;
{

    use File::Basename ();
    use constant DIR => File::Basename::dirname(readlink(__FILE__) || __FILE__);
    use lib DIR . "/../extlib/lib/perl5";

    # required modules
    use Cwd         ();
    use Carp        ();
    use IO::Socket  ();
    use HTTP::Tiny  ();

    #use Time::HiRes      (); # lazy
    #use POSIX            (); # lazy
    #use File::Path       (); # lazy
    #use Text::ParseWords (); # lazy
    #use File::Temp       (); # lazy


    BEGIN {
        if (eval { require JSON::XS }) {
            *encode_json = \&JSON::XS::encode_json;
            *decode_json = \&JSON::XS::decode_json;
        }
        else {
            require JSON;
            *encode_json = \&JSON::encode_json;
            *decode_json = \&JSON::decode_json;
        }
    }

    my $jsx_compiler = DIR . "/../bin/jsx-compiler.js";

    my $home = $ENV{JSX_HOME} || (($ENV{HOME} || glob('~')) . "/.jsx");

    my $pid_file  = "$home/pid";
    my $port_file = "$home/port";
    my $log_file  = "$home/server.log";
    my $run_dir   = "$home/run";

    if (not -d $run_dir) {
        require File::Path;
        File::Path::mkpath($home . "/run");
    }

    my $ua = HTTP::Tiny->new(
        agent => __PACKAGE__,
    );

    sub read_file {
        my($file) = @_;
        open my($fh), "<", $file or Carp::confess("cannot open file '$file' for reading: $!");
        local $/;
        return scalar <$fh>;
    }

    sub write_file {
        my($file, $content) = @_;
        open my($fh), ">", $file or Carp::confess("cannot open file '$file' for writing: $!");
        print $fh $content;
        close $fh or Carp::confess("cannot close file '$file': $!");
        return;
    }

    sub server_running {
        if (-f $port_file) {
            chomp(my $port = read_file($port_file));
            my $res = $ua->request(GET => "http://localhost:$port/ping");
            return $res->{success};
        }
        else {
            return 0;
        }
    }

    sub get_server_port {
        if (! server_running()) {
            unlink($port_file);

            my $parent_pid = $$;
            defined(my $pid = fork()) or Carp::confess("failed to fork: $!");

            if ($pid == 0) {
                # child process
                open STDOUT, ">>", $log_file or Carp::confess("cannot open '$log_file' for writing: $!");
                open STDERR, ">&", \*STDOUT or Carp::confess("cannot dup STDOUT: $!");

                require POSIX;
                POSIX::setsid();

                my $port = empty_port();
                exec($jsx_compiler, "--compilation-server", $port)
                    or kill(TERM => $parent_pid), Carp::confess("failed to exec $jsx_compiler: $!");
                die "not reached";
            }
            # parent process
        }
        until (server_running()) {
            require Time::HiRes;
            Time::HiRes::sleep(0.100);
        }
        return read_file($port_file);
    }

    sub prepare_run_command {
        my($run) = @_;

        my $js = $ENV{JSX_RUNJS} || "node";

        require File::Temp;
        my($fh, $file) = File::Temp::tempfile(
            DIR    => $run_dir,
            SUFFIX => ".js",
            UNLINK => 1,
        );
        print $fh $run->{scriptSource};
        close $fh;

        my $scriptArgs = $run->{scriptArgs};
        return ($js, $file, @{$scriptArgs});
    }

    sub request { # returns JSON response
        my($port, @args) = @_;

        my %options;
        # can read bytes from STDIN?
        my $rbits = '';
        vec($rbits, fileno(STDIN), 1) = 1;
        if (select($rbits, undef, undef, 0)) {
            local $/;
            $options{'headers'} = {'content-type' => 'text/plain'};
            $options{'content'} = <STDIN>;
        }

        my @real_args = ("--working-dir", Cwd::getcwd(), @args);

        my $res = $ua->request(POST =>
            "http://localhost:$port/compiler?" . encode_json(\@real_args),
            \%options);

        if (!( $res->{success} && $res->{headers}{'content-type'} eq 'application/json')) {
            return {
                statusCode => 2,
                stdout     => "",
                stderr     => $res->{content},
            };
        }
        return decode_json($res->{content});
    }

    sub main {
        my(@argv) = @_;

        if (! @argv) {
            print "no files\n";
            return 1;
        }

        my $restart;
        @argv = grep { $_ eq '--restart' ? !++$restart : 1 } @argv;
        if ($restart && -f $pid_file) {
            kill TERM => read_file($pid_file);
            unlink $pid_file, $port_file;
        }

        my $port = get_server_port();
        my $c = request($port, @argv);
        for my $filename(keys %{$c->{file}}) {
            write_file($filename, $c->{file}{$filename});
        }
        for my $filename(keys %{$c->{executableFile}}) {
            if ($c->{executableFile}{$filename} eq "node") {
                chmod(0755, $filename);
            }
        }
        if ($c->{run}) {
            return system(prepare_run_command($c->{run}));
        }
        else {
            print STDOUT $c->{stdout};
            print STDERR $c->{stderr};
            return $c->{statusCode};
        }
    }


    # copied from Test::TCP
    sub empty_port {
        my $port = do {
            if (@_) {
                my $p = $_[0];
                $p = 49152 unless $p =~ /^[0-9]+$/ && $p < 49152;
                $p;
            } else {
                50000 + int(rand()*1000);
            }
        };

        while ( $port++ < 60000 ) {
            next if _check_port($port);
            my $sock = IO::Socket::INET->new(
                Listen    => 5,
                LocalAddr => '127.0.0.1',
                LocalPort => $port,
                Proto     => 'tcp',
                (($^O eq 'MSWin32') ? () : (ReuseAddr => 1)),
            );
            return $port if $sock;
        }
        die "empty port not found";
    }

    sub _check_port {
        my ($port) = @_;

        my $remote = IO::Socket::INET->new(
            Proto    => 'tcp',
            PeerAddr => '127.0.0.1',
            PeerPort => $port,
        );
        if ($remote) {
            close $remote;
            return 1;
        }
        else {
            return 0;
        }
    }
} # App::jsx

package main;
exit(App::jsx::main(@ARGV)) if $0 eq __FILE__;
1;
package OuterShell;

require "./".$ARGV[0]."__packaging__/innershell.pm";

sub puts {
    my $d0 = $_[0];
    if (exists $InnerShell::STACK{$d0}) {
        print $InnerShell::STACK{$d0};
    } else {
        print $d0;
    }
}

sub update {
    my $d0 = $_[0];
    my $d1 = $_[1];

    if (exists $InnerShell::STACK{$d1}) {
        $d1 = $InnerShell::STACK{$d1};
    }

    if (length($d0) > 2) {
        if (!exists $InnerShell::REGISTERS{$d0}) {
            print "<FATAL-Error>\n|> Reason: Invalid register location: " . $register . "\n";
            die;
        }
        &InnerShell::setRegister($d0, $d1);
    } else {
        if (!exists $InnerShell::STACK{$d0}) {
            if ($InnerShell::WARN == 1) {
                print "Attempt to assign value to uninitalized data point: " . $d0 . "\n";
            }
            &InnerShell::store($d0, $d1);
        }
        &InnerShell::store($d0, $d1);
    }
}

sub add {
    my $d0 = $_[0];
    my $d1 = $_[1];
    my $register = $_[2];
    &InnerShell::setRegister($register, $d0 + $d1);
}

sub subt {
    my $d0 = $_[0];
    my $d1 = $_[1];
    my $register = $_[2];
    &InnerShell::setRegister($register, $d0 - $d1);
}

sub mul {
    my $d0 = $_[0];
    my $d1 = $_[1];
    my $register = $_[2];
    &InnerShell::setRegister($register, $d0 * $d1);
}

sub div {
    my $d0 = $_[0];
    my $d1 = $_[1];
    my $register = $_[2];
    &InnerShell::setRegister($register, $d0 / $d1);
}

sub exp {
    my $d0 = $_[0];
    my $d1 = $_[1];
    my $register = $_[2];
    &InnerShell::setRegister($register, $d0 ** $d1);
}

sub read {
    my $d0 = $_[0];
    my $stdin = <STDIN>;
    chomp $stdin;
    &InnerShell::store($d0, $stdin);
}

sub compare {
    my $d0 = $_[0];
    my $d1 = $_[1];
    my $d2 = $_[2];

    if (length($d0) > 3) {
        $d0 = $InnerShell::STACK{$d0};
    } else {
        print "WIP";
    }

    if (length($d1) > 3) {
        $d1 = $InnerShell::STACK{$d1};
    } else {
        print "WIP";
    }

    if ($d0 eq $d1) {
        &InnerShell::setRegister($d2, 0);
    } else {
        &InnerShell::setRegister($d2, 1);
    }
}

1;


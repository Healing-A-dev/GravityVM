package OuterShell;

require "./__packaging__/innershell.pm";

sub puts {
    my $key = $_[0];
    if (exists $InnerShell::STACK{$key}) {
        print $InnerShell::STACK{$key};
    } else {
        print $key;
    }
}

sub update {
    my $d0 = $_[0];
    my $d1 = $_[1];
    my @chars = split(undef, $d0);

    if ($chars[0] ne "[") {
        if (!exists $InnerShell::STACK{$d0}) {
            if ($InnerShell::WARN eq 1) {
                print "Attempt assign value to uninitalized data point: " . $d0 . "\n";
            }
            &InnerShell::store($d0, $d1);
        }
        &InnerShell::store($d0, $d1);
    } elsif ($chars[0] eq "[") {
        $d0 = substr($d0, 1, length($d0) - 2);
        &InnerShell::setRegister($d0, $d1);
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

1;


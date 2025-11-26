import strutils
var packaging_location*: string = ""


# INNER SHELLING #
const innershell*: string = """package InnerShell;

our %STACK = ();
our %REGISTERS = (
    sra => 0,
    srb => 0,
    src => 0,
    srd => 0,
    sre => 0,
);
our $WARN = 0;

sub store {
    my $variable = $_[0];
    my $data = $_[1];
    $STACK{$variable} = $data;
}

sub setRegister {
    my $register = $_[0];
    my $value = $_[1];

    if (!exists $REGISTERS{$register}) {
        print "<FATAL-Error>\n|> Reason: Invalid register location: " . $register . "\n";
        die;
    }

    $REGISTERS{$register} = $value;
}

sub moveRegister {
    my $register = $_[0];
    my $memory_location = $_[1];
    $STACK{$memory_location} = $REGISTERS{$register};
}

sub getRegister {
    my $register = $_[0];
    if (!exists $REGISTERS{$register}) {
        print "<FATAL-Error>\n|> Reason: Invalid register location: " . $register . "\n";
        die;
    }
    return $REGISTERS{$register};
}


1;
"""

# OUTER SHELLING #
var outershell_header: seq[string] = @["package OuterShell;\n", "require \"./\".$ARGV[0].\"" & packaging_location & "__packaging__/innershell.pm\";\n\n"]
var outershell*:string = outershell_header.join("\n") & """sub puts {
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
"""

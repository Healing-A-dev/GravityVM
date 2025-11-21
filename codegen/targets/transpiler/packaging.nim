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



1;
"""

# OUTER SHELLING #
var outershell_header: seq[string] = @["package OuterShell;\n", "require \"./" & packaging_location & "__packaging__/innershell.pm\";\n\n"]
var outershell*:string = outershell_header.join("\n") & """sub puts {
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
"""

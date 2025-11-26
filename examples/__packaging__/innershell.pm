package InnerShell;

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


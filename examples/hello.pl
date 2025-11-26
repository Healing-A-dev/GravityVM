=pod
 > Transpiled hello.gravity file
 > Generated from the newly implemented fallback feature
 > Implements packaing path finder:
     > $packagingPath ::= First command line argument
     > Automaticly entered if ran with Gravity
=cut

# Packaging
my $packagingPath = $ARGV[0];
require "./".$packagingPath."__packaging__/innershell.pm";
require "./".$packagingPath."__packaging__/outershell.pm";
# Program examples/hello.gravity
sub main {
    &InnerShell::store("L02_gravityV", 100);
    &InnerShell::store("L03_gravityV", "Healing");
    &InnerShell::store("L04_gravityV", 0);
    &InnerShell::store("L05_gravityV", 5);
    &InnerShell::store("L06_gravityV", "QUIT");
    &InnerShell::store("L07_gravityV", "Quit");
    &InnerShell::store("L08_gravityV", "quit");
    &InnerShell::store("L09_gravityV", "nice");
    &InnerShell::store("L04_gravityV", 1);

lblDo_AGAIN:
    &OuterShell::puts("Enter the correct name: ");
    &OuterShell::read("L01_gravityV");
    &OuterShell::compare("L01_gravityV", "L06_gravityV", "sra");
    goto lblQUIT if ($InnerShell::REGISTERS{"sra"} == 0);
    &OuterShell::compare("L01_gravityV", "L07_gravityV", "sra");
    goto lblQUIT if ($InnerShell::REGISTERS{"sra"} == 0);
    &OuterShell::compare("L01_gravityV", "L08_gravityV", "sra");
    goto lblQUIT if ($InnerShell::REGISTERS{"sra"} == 0);
    &OuterShell::compare("L01_gravityV", "L09_gravityV", "sra");
    goto lblnice if ($InnerShell::REGISTERS{"sra"} == 0);
    &OuterShell::compare("L03_gravityV", "L01_gravityV", "sra");
    goto lblWRONG if ($InnerShell::REGISTERS{"sra"} != 0);
    &OuterShell::puts("Hello ");
    &OuterShell::puts("\033[32m");
    &OuterShell::puts("L01_gravityV");
    &OuterShell::puts("\033[0m!");
    &OuterShell::puts("\n");
    &OuterShell::puts("\n");
    &OuterShell::puts("-------------------------------\n");
    &OuterShell::puts("Congraulations on guessing the correct name!\n");
    &OuterShell::puts("Your prize is....NOTHINGGGG :D\n");
    exit 0;
lblWRONG:
    &OuterShell::puts("Incorrect Name: ");
    &OuterShell::puts("\033[91m");
    &OuterShell::puts("L01_gravityV");
    &OuterShell::puts("\033[0m\n");
    &OuterShell::add("L04_gravityV", 1, "sra");
    &InnerShell::store("L04_gravityV", &InnerShell::getRegister("sra"));
    &OuterShell::compare("L04_gravityV", "L05_gravityV", "sra");
    goto lblHINT if ($InnerShell::REGISTERS{"sra"} == 0);
    goto lblDo_AGAIN;
lblHINT:
    &OuterShell::puts("Hint: Its the nickname of the creator of gravity :)");
    goto lblDo_AGAIN;
lblQUIT:
    &OuterShell::puts("Okay :)\n");
    exit 69;
lblnice:
    &OuterShell::puts("I know right\n");
    goto lblDo_AGAIN;

}
&main();

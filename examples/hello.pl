require "./__packaging__/innershell.pm";
require "./__packaging__/outershell.pm";
sub main {
    &InnerShell::store("L02_gravityV", 100);
    &InnerShell::store("L03_gravityV", "Healing");

lblDo_AGAIN:
    &OuterShell::puts("Enter the correct name: ");
    &OuterShell::read("L01_gravityV");
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
    goto lblDo_AGAIN

}
&main();

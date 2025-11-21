require "./__packaging__/innershell.pm";
require "./__packaging__/outershell.pm";
sub main {
    &OuterShell::puts("Enter your name: ");
    &OuterShell::read("L01_gravityV");
    &OuterShell::puts("Hello ");
    &OuterShell::puts("L01_gravityV");
    &OuterShell::puts("!");
    &OuterShell::puts("
");

}
&main();

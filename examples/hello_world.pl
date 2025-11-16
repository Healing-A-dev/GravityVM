# Transpiled from hello_world.gravity to perl
# Only transpiles when forced, or target (ie. x86_64) is not supported/ implemented (yet)
# Compiles to a native executable otherwise

sub main() {
    our $G01_gravityV = "This was written in gravity :>\n";

    print("Hello, World\n");
    print("This was compiled using the GravityVM\n");
    print("\n");
    print($G01_gravityV);

}
&main()

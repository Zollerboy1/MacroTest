@attached(accessor, names: named(didSet))
public macro Test() = #externalMacro(
    module: "MacroTestImpl",
    type: "TestMacro"
)


@Test
var foo = "foo"

// Uncommenting this line cases the compiler to crash
//@Test
var bar = "bar" {
    didSet {
        print("bar was set to \(bar)")
    }
}

foo = "baz"
bar = "baz"

# Manual


## Defining tests

The entry-point file (commonly called `runtests.jl`) is simply:

```julia
using Jute
exit(runtests())
```

The test runner picks up any file with the name ending in `.test.jl` in the directory where the entry-point file is located, or in any subdirectories.
All those files are included at the same level (with `using Jute` at the start), and all the [`@testcase`](@ref Jute.@testcase) and [`@testgroup`](@ref Jute.@testgroup) definitions are picked up.
The [`@testgroup`](@ref Jute.@testgroup) definitions can contain other [`@testgroup`](@ref Jute.@testgroup) definitions and [`@testcase`](@ref Jute.@testcase) definitions.

The `exit()` call is required to signal about any test failures to the processes that initiate the execution of the test suite, for instance CI tools.
[`runtests()`](@ref Jute.runtests) returns `1` if there were failed tests, `0` otherwise.

The [`@testcase`](@ref Jute.@testcase) macro takes the testcase name and body:

```julia
@testcase "simple testcase" begin
    @test 1 == 1
end
```


## Assertions

`Jute` relies on the assertions from [`Base.Test`](http://docs.julialang.org/en/latest/stdlib/test/); [`@test`](@ref Jute.@test), [`@test_throws`](@ref Jute.@test_throws), [`@test_skip`](@ref Jute.@test_skip) and [`@test_broken`](@ref Jute.@test_broken) can be used.
In addition, `Jute` has a [`@test_result`](@ref Jute.@test_result) macro allowing one to return a custom result (e.g. the value of a benchmark from a testcase).
There can be several assertions per testcase; their results will be reported separately.
If the testcase does not call any assertions and does not throw any exceptions, it is considered to be passed.


## Grouping tests

Testcases can be grouped using [`@testgroup`](@ref Jute.@testgroup) definitions.
For example:

```julia
@testcase "tc1" begin
end

@testgroup "group" begin
    @testcase "tc2" begin
    end
end

@testgroup "group2" begin
    @testgroup "subgroup" begin
        @testcase "tc3" begin
        end
    end
end
```

the following testcases will be listed:

```
tc1
Group/tc2
Group2/Subgroup/tc3
```

The order of testcase definition is preserved.
In other words, the testcases will be executed in the same order in which they were defined.


## Parametrizing testcases


### Constant fixtures

The simplest method to parametrize a test is to supply it with an iterable:

```julia
@testcase "parametrized testcase" for x in [1, 2, 3]
    @test x == 1
end

# Output:
# parametrized testcase[1]: [PASS]
# parametrized testcase[2]: [FAIL]
# parametrized testcase[3]: [FAIL]
```

By default, `Jute` uses `string()` to convert a fixture value to a string for reporting purposes.
One can assign custom labels to fixtures by passing a `Pair` of iterables instead:

```julia
@testcase "parametrized testcase" for x in [1, 2, 3] => ["one", "two", "three"]
    @test x == 1
end

# Output:
# parametrized testcase[one]: [PASS]
# parametrized testcase[two]: [FAIL]
# parametrized testcase[three]: [FAIL]
```

A testcase can use several fixtures, in which case `Jute` will run the testcase function will all possible combinations of them:

```julia
@testcase "parametrized testcase" for x in [1, 2], y in [3, 4]
    @test x + y == y + x
end

# Output:
# parametrized testcase[1, 3]: [PASS]
# parametrized testcase[1, 4]: [PASS]
# parametrized testcase[2, 3]: [PASS]
# parametrized testcase[2, 4]: [PASS]
```


### Global fixtures

A global fixture is a more sophisticated variant of a constant fixture that has a setup and a teardown stage.
For each value produced by the global fixture, the setup is called before the first testcase that uses it.
As for the teardown, it is either called right away (if the keyword parameter `instant_teardown` is `true`), or after the last testcase that uses it (if `instant_teardown` is `false`, which is the default).
If no testcases use it (for example, they were filtered out), neither setup nor teardown will be called.

The setup and the teardown are defined by use of a single coroutine that produces the fixture value.
The coroutine's first argument is a function that is used to return the value.
If `instant_teardown` is `false`, the call blocks until it is time to execute the teardown:

```julia
db_connection = fixture() do produce
    c = db_connect()

    # this call blocks until all the testcases
    # that use this value are executed
    produce(c)

    close(c)
end
```

Similarly to the constant fixture case, one can provide a custom identifier for the fixture via the optional second argument of `produce()`:

```julia
db_connection = fixture() do produce
    c = db_connect()

    produce(c, "db_connection")

    close(c)
end
```

Global fixtures can be parametrized by other constant or global fixtures.
Similarly to the test parametrization, all possible combinations of parameters will be used to produce values:

```julia
fx1 = fixture(3:4) do produce, x
    produce(x)
end

fx2 = fixture(1:2, fx1) do produce, x, y
    produce((x, y))
end

@testcase "tc" for x in fx2
    @test length(x) == 2
end

# Output:
# tc[(1, 3)]: [PASS]
# tc[(1, 4)]: [PASS]
# tc[(2, 3)]: [PASS]
# tc[(2, 4)]: [PASS]
```


### Local fixtures

A local fixture is a fixture whose value is created right before each call to the testcase function and destroyed afterwards.
A simple example is a fixture that provides a temporary directory:

```julia
temporary_dir = local_fixture() do produce
    dir = mktempdir()
    produce(dir) # this call will block while the testcase is being executed
    rm(dir, recursive=true)
end

@testcase "tempdir test" for dir in temporary_dir
    open(joinpath(dir, "somefile"), "w")
end
```

Local fixtures can be parametrized by any other type of fixture, including other local fixtures.


## Testcase tags

Testcases can be assigned tags of the type `Symbol`.
This can be used to establish a secondary grouping, independent of the primary grouping provided by modules.
For example, one can tag performance tests, tests that run for a long time, unit/integration tests, tests that require a specific resource and so on.
Testcases can be filtered by tags they have or don't have using [command-line arguments](@ref run_options_manual).

The tagging is performed by an optional paramter `tag` to the macro [`@testcase`](@ref Jute.@testcase) that takes a list of `Symbol`s:

```julia
@testcase tags=[:foo] "tc" begin
    ... something
end
```


## [Run options](@id run_options_manual)

`Jute`'s [`runtest()`](@ref Jute.runtests) picks up the options from the command line by default.
Alternatively, they can be set with the `options` keyword argument of [`runtests()`](@ref Jute.runtests).

```@docs
Jute.build_parser
```

Run options can be accessed from a testcase or a fixture via the built-in fixture [`run_options`](@ref Jute.run_options).
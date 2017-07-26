using IterTools: chain

import Base.Test
const BT = Base.Test


mutable struct JuteTestSet <: BT.AbstractTestSet
    results :: Array{BT.Result, 1}

    JuteTestSet(descr; results=[]) = new(results)
end


function Base.Test.record(ts::JuteTestSet, res::BT.Result)
    push!(ts.results, res)
end


function Base.Test.finish(ts::JuteTestSet) end


function run_testcase(tc::Testcase, args)
    succeeded = true
    results = BT.Result[]

    tic()
    BT.@testset JuteTestSet results=:($results) begin
        Base.invokelatest(tc.func, args...)
    end
    elapsed_time = toq()

    if length(results) == 0
        push!(results, BT.Pass(:test, nothing, nothing, nothing))
    end

    TestcaseOutcome(results, elapsed_time)
end


_get_iterable(global_fixtures, fx::GlobalFixture) = global_fixtures[fx]
_get_iterable(global_fixtures, fx::ConstantFixture) = fx
_get_iterable(global_fixtures, fx::LocalFixture) =
    rowmajor_product([_get_iterable(global_fixtures, param) for param in parameters(fx)]...)

get_iterable(global_fixtures) = fx -> _get_iterable(global_fixtures, fx)


struct DelayedValue
    pair
    rff :: RunningFixtureFactory
    subvalues :: Array{DelayedValue, 1}
end


function setup(fx::LocalFixture, args)
    to_release = []
    processed_args = []
    for (p, arg) in zip(parameters(fx), args)
        if typeof(p) == LocalFixture
            val = setup(p, arg)
            push!(to_release, val)
            arg = val.pair
        end
        push!(processed_args, arg[1])
    end
    pair, rff = setup(fx.ff, processed_args)
    DelayedValue(pair, rff, to_release)
end


function release(val::DelayedValue)
    for v in val.subvalues
        release(v)
    end
    teardown(val.rff)
end
function release(val) end


unwrap_value(val::DelayedValue) = val.pair[1]
unwrap_value(val) = val[1]
unwrap_id(val::DelayedValue) = val.pair[2]
unwrap_id(val) = val[2]

unwrap_pair(val::DelayedValue) = val.pair
unwrap_pair(val) = val



function run_testcases(run_options::RunOptions, tcs)

    global_fixtures = Dict()
    gi = get_iterable(global_fixtures)
    for_teardown = Dict()
    function add_for_teardown(idx, rffs)
        if haskey(for_teardown, idx)
            append!(for_teardown[idx], rffs)
        else
            for_teardown[idx] = rffs
        end
    end

    test_outcomes = []

    progress = progress_reporter([name_tuple for (name_tuple, tc) in tcs], run_options.verbosity)

    progress_start!(progress)

    for (i, entry) in enumerate(tcs)

        name_tuple, tc = entry

        for fx in dependencies(tc)
            if typeof(fx) == GlobalFixture && !haskey(global_fixtures, fx)

                ftd = []

                iterables = gi.(parameters(fx))

                all_pairs = []
                for val_pairs in rowmajor_product(iterables...)
                    args = unwrap_value.(val_pairs)
                    iterable, rff = setup(fx, args)
                    push!(all_pairs, iterable)
                    if delayed_teardown(rff)
                        push!(ftd, rff)
                    else
                        teardown(rff)
                    end
                end

                global_fixtures[fx] = chain(all_pairs...)

                if length(ftd) > 0
                    last_usage_idx = findlast(tcs) do entry
                        _, tcc = entry
                        fx in tcc.dependencies
                    end
                    add_for_teardown(last_usage_idx, ftd)
                end
            end
        end

        fixture_iterables = gi.(parameters(tc))

        instantiate(fx::LocalFixture, pair) = setup(fx, pair)
        instantiate(fx, pair) = pair

        iterable_permutations = rowmajor_product(fixture_iterables...)

        progress_start_testcases!(progress, name_tuple, length(iterable_permutations))

        for val_pairs in iterable_permutations
            actual_args = instantiate.(parameters(tc), val_pairs)
            args = unwrap_value.(actual_args)
            ids = unwrap_id.(actual_args)
            outcome = run_testcase(tc, args)
            release.(actual_args)
            push!(test_outcomes, (name_tuple, ids, outcome))
            progress_finish_testcase!(progress, name_tuple, ids, outcome)
        end

        if haskey(for_teardown, i)
            teardown.(for_teardown[i])
        end

        progress_finish_testcases!(progress, name_tuple)
    end

    progress_finish!(progress, test_outcomes)

end


function is_testcase_included(run_options::RunOptions, name_tuple)
    full_tag = join(name_tuple, "/") # FIXME: should be standartized
    exclude = run_options.exclude
    include_only = run_options.include_only
    (
        (isnull(exclude) || !ismatch(get(exclude), full_tag))
        && (isnull(include_only) || ismatch(get(include_only), full_tag))
        )
end


function filter_testcases(run_options::RunOptions, tcs)
    filter(p -> is_testcase_included(run_options, p[1]), tcs)
end


function sort_testcases(tcs)
    sort(tcs, by=p -> tuple(p[1][1:end-1]..., p[2].order))
end


function runtests_internal(run_options, obj_dict)
    if run_options.verbosity > 0
        println("Collecting testcases...")
    end
    all_testcases = get_testcases(run_options, obj_dict)
    testcases = filter_testcases(run_options, all_testcases)
    testcases = sort_testcases(testcases)

    if run_options.verbosity > 0
        println("Running $(length(testcases)) out of $(length(all_testcases)) testcases...")
        println("=" ^ 80)
    end
    all_successful = run_testcases(run_options, testcases)
    Int(!all_successful)
end


function runtests()
    run_options = build_run_options(ARGS)
    runtests_dir = get_runtests_dir()
    test_files = find_test_files(runtests_dir, run_options.test_file_postfix)

    if run_options.verbosity > 0
        println("Loading test files...")
    end
    obj_dict = include_test_files!(
        test_files, run_options.dont_add_runtests_path ? nothing : runtests_dir)

    runtests_internal(run_options, obj_dict)
end

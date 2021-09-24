#! /bin/sh

set -e

usage () {
    cat >&2 <<EOF
usage: $0 cmd

EOF
}

extratest=$(mktemp -t testXXXx.ml)
test_one () {
    local tz_path="$1"
    local output_path="$2"
    rm -fr "$output_path"
    mkdir -p "$output_path/lib" "$output_path/test"
    testml=$output_path/test/main.ml
    cat > "$testml" <<EOF
let say fmt = Format.kasprintf (Printf.eprintf "test-> %s\n%!") fmt
open Test_library.Contract
let assert_string a b = 
  say "Testing: %s" a ;
  if a = b then () else
    Format.kasprintf failwith "TEST-ASSERT-FAILURE: %S <> %S" a b
EOF
    cat $extratest >> "$testml"
    cat >> "$testml" <<EOF
let () = say "TEST $(basename $tz_path) SUCCEEDED"
EOF
    dune exec src/app/main.exe -- ocaml "$tz_path" \
             --output-dune test_library \
             "$output_path/lib/contract.ml"
    echo "GENERATED $output_path/lib/contract.ml"
    echo '(executables (names main) (libraries test_library))' >> $output_path/test/dune
    (
        cd "$output_path"
        ocamlformat --inplace --enable-outside-detected-project lib/contract.ml
        dune build --root=$PWD @check
        dune build --root=$PWD @doc
        dune exec --root=$PWD test/main.exe
    )
}

run_all () {
    testpath=_build/ocamlgentest
    tezos_entrypoints=local-vendor/tezos-master/tests_python/contracts_010/entrypoints
    tezos_scenarios=local-vendor/tezos-master/tests_python/contracts_010/mini_scenarios

    one_address=tz1L1bypLzuxGHmx3d6bHFJ2WCi4ZDbocSCA
    cat > $extratest <<EOF
let () =
  assert_string
    Parameter.(Remove_delegate M_unit.Unit |> to_concrete)
    "(Left (Right Unit))" ;
  let setting_delegate =
    Parameter.Set_delegate M_key_hash.(Raw_b58 "$one_address") in
  assert_string
    Parameter.(setting_delegate |> to_concrete)
    "(Left (Left \"$one_address\"))" ;
  let \`Name ep, \`Literal lit =
    Parameter.to_concrete_entry_point setting_delegate in
  assert_string ep "set_delegate" ;
  assert_string lit "\"$one_address\"" ;
  begin match (Parameter.of_json (\`O [
     "prim", \`String "Left"; 
     "args", \`A [
        \`O[
           "prim", \`String "Right"; 
           "args", \`A [
             \`O ["prim", \`String "Unit"; "args", \`A []]
           ]
       ]
      ]
    ])) with
   | Ok (Parameter.Remove_delegate M_unit.Unit) -> ()
   | Error (\`Of_json (s, _)) -> failwith s
   | _other -> assert false
  end;
  ()
EOF
    test_one \
        "$tezos_entrypoints/delegatable_target.tz" \
        "$testpath/epdele/" \

    cat > $extratest <<EOF
let () =
  assert_string
    "(Pair \"hello\" 42)"
    Storage.(make ~storage_1:M_string.(Raw_string "hello")
              ~storage_0:M_nat.(Big_int Big_int.(big_int_of_int 42))
             |> to_concrete)
EOF
    test_one \
        "$tezos_entrypoints/no_default_target.tz" \
        "$testpath/epndt/"

    # FAILS becuase of lambdas:
    lambda="{ PUSH nat 42; ADD }"
    cat > $extratest <<EOF
let () =
  assert_string
    "(Left $lambda)"
    Parameter.(Do M_lambda.(Concrete_raw_string "$lambda")
               |> to_concrete)
EOF
    test_one \
        "$tezos_entrypoints/manager.tz" \
        "$testpath/epmana/"

}


if [ "$1" = "" ] || [ "$1" = "--help" ] ; then
    usage
else
    "$@"
fi

open Internal_pervasives

module Michelson = struct
  let prepare_origination_of_id_script ?delegate ?(push_drops = 0)
      ?(amount = "2") state ~name ~from ~protocol_kind ~parameter ~init_storage
      =
    let id_script parameter =
      Fmt.strf
        "parameter %s;\n\
         storage %s;\n\
         code\n\
        \  {\n\
        \    %s\n\
        \    { CAR; NIL operation; PAIR }\n\
        \  };\n"
        parameter parameter
        ( match push_drops with
        | 0 -> "# No push-drops"
        | n ->
            Fmt.strf "# %d push-drop%s\n    %s" n
              (if n > 1 then "s" else "")
              ( List.init push_drops ~f:(fun ith ->
                    Fmt.strf "{ PUSH string %S ; DROP } ;"
                      (Fmt.strf
                         "push-dropping %d adds stupid bytes to the contract"
                         ith))
              |> String.concat ~sep:"\n    " ) ) in
    let tmp = Caml.Filename.temp_file "little-id-script" ".tz" in
    System.write_file state tmp ~content:(id_script parameter)
    >>= fun () ->
    Dbg.e EF.(wf "id_script %s: %s" parameter tmp) ;
    let origination =
      let opt = Option.value_map ~default:[] in
      ["--wait"; "none"; "originate"; "contract"; name]
      @ ( match protocol_kind with
        | `Athens -> ["for"; from]
        | `Carthage | `Babylon -> [] )
      @ [ "transferring"; amount; "from"; from; "running"; tmp; "--init"
        ; init_storage; "--force"; "--burn-cap"; "300000000000"
        ; (* ; "--fee-cap" ; "20000000000000" *) "--gas-limit"
        ; "1000000000000000"; "--storage-limit"; "20000000000000"
        ; "--verbose-signing" ]
      @ opt delegate ~f:(fun s -> (* Baby & Aths *) ["--delegate"; s]) in
    return origination
end

module Forge = struct
  let batch_transfer
      ?(protocol_kind : Tezos_protocol.Protocol_kind.t = `Babylon)
      ?(counter = 0) ?(dst = [("tz2KZPgf2rshxNUBXFcTaCemik1LH1v9qz3F", 1)])
      ~src ~fee ~branch n : Ezjsonm.value =
    let open Ezjsonm in
    ignore protocol_kind ;
    dict
      [ ("branch", `String branch)
      ; ( "contents"
        , `A
            (List.map (List.range 0 n) ~f:(fun i ->
                 let dest, amount = List.nth_exn dst (i % List.length dst) in
                 `O
                   [ ("kind", `String "transaction")
                   ; ("source", `String src)
                   ; ("destination", `String dest)
                   ; ("amount", `String (Int.to_string amount))
                   ; ( "fee"
                     , `String (Int.to_string (Float.to_int (fee *. 1000000.)))
                     )
                   ; ("counter", `String (Int.to_string (counter + i)))
                   ; ("gas_limit", `String (Int.to_string 127))
                   ; ("storage_limit", `String (Int.to_string 277)) ])) ) ]

  let endorsement ?(protocol_kind : Tezos_protocol.Protocol_kind.t = `Babylon)
      ~branch level : Ezjsonm.value =
    let open Ezjsonm in
    ignore protocol_kind ;
    dict
      [ ("branch", `String branch)
      ; ( "contents"
        , `A [`O [("kind", `String "endorsement"); ("level", int level)]] ) ]

  let signer_names_base =
    [ "Alice"; "Bob"; "Charlie"; "David"; "Elsa"; "Frank"; "Gail"; "Harry"
    ; "Ivan"; "Jane"; "Iris"; "Jackie"; "Linda"; "Mary"; "Nemo"; "Opal"; "Paul"
    ; "Quincy"; "Rhonda"; "Steve"; "Theodore"; "Uma"; "Venus"; "Wimpy"
    ; "Xaviar"; "Yuri"; "Zed" ]

  let get_signer_names signers n =
    let k = List.length signers in
    let rec append = function 0 -> signers | x -> signers @ append (x - 1) in
    let suffix = function 0 -> "" | n -> "-" ^ Int.to_string (n + 1) in
    let fold_f ((xs, i) : string list * int) (x : string) : string list * int =
      let fst = List.cons (x ^ suffix (i / k)) xs in
      (fst, i + 1) in
    let big_list = List.take (append (n / k)) n in
    let result, _ = List.fold big_list ~init:([], 0) ~f:fold_f in
    List.rev result

  (* TODO: Do we want this here?  The API is quite different from the others *)
  let run_multi_sig state client nodes ~num_signers ~outer_repeat
      ~contract_repeat =
    let signer_names = get_signer_names signer_names_base num_signers in
    (*loop through batch size *)
    Loop.n_times outer_repeat (fun n ->
        (* generate and import keys *)
        let signer_names = List.take signer_names num_signers in
        Helpers.import_keys state client signer_names
        (* deploy the multisig contract *)
        >>= fun _ ->
        Test_scenario.Queries.wait_for_bake state ~nodes
        (* required to avoid "counter" errors *)
        >>= fun () ->
        let multisig_name = "msig-" ^ Int.to_string n in
        Tezos_client.deploy_multisig state client ~name:multisig_name
          ~amt:100.0 ~from_acct:"bootacc-0" ~threshold:num_signers
          ~signer_names ~burn_cap:100.0
        >>= fun () ->
        Test_scenario.Queries.wait_for_bake state ~nodes
        >>= fun () ->
        (* for each signer, sign the contract *)
        let m_sigs =
          List.map signer_names ~f:(fun s ->
              Tezos_client.sign_multisig state client ~name:multisig_name
                ~amt:100.0 ~to_acct:"Bob" ~signer_name:s) in
        Asynchronous_result.all m_sigs
        >>= fun signatures ->
        (* submit the fully signed multisig contract *)
        Loop.n_times contract_repeat (fun k ->
            Tezos_client.transfer_from_multisig state client
              ~name:multisig_name ~amt:100.0 ~to_acct:"Bob"
              ~on_behalf_acct:"bootacc-0" ~signatures ~burn_cap:100.0
            >>= fun () ->
            Console.say state
              EF.(
                desc
                  (haf "Multi-sig contract generation")
                  (af "Fully signed contract %s (%n) submitted" multisig_name k))))
end

module Random = struct
  let run state ~protocol ~nodes ~clients ~until_level kind =
    assert (Poly.equal kind `Any) ;
    let tbb =
      protocol.Tezos_protocol.time_between_blocks |> List.hd
      |> Option.value ~default:10 in
    let info fmt =
      Fmt.kstr
        (fun s ->
          Console.sayf state Fmt.(fun ppf () -> pf ppf "Randomizer: %s" s))
        fmt in
    let from = "bootacc-0" in
    let client = List.hd_exn clients in
    let pp_success ppf = function
      | true -> Fmt.pf ppf "Success"
      | false -> Fmt.pf ppf "Failure" in
    let valid_contracts = ref [] in
    let rec loop iteration =
      let client_cmd name l =
        Tezos_client.client_cmd ~verbose:false state ~client
          ~id_prefix:(Fmt.str "randomizer-%04d-%s" iteration name)
          l in
      let continue_or_not () =
        Test_scenario.Queries.all_levels state ~nodes
        >>= fun all_levels ->
        if
          List.for_all all_levels ~f:(function
            | _, `Level l when l >= until_level -> true
            | _ -> false)
        then info "Max-level reached: %d" until_level
        else loop (iteration + 1) in
      List.random_element
        [`Sleep; `Add_contract; `Call_contract; `Multisig_contract]
      |> function
      | Some `Sleep ->
          let secs =
            Float.(Random.float_range (of_int tbb * 0.3) (of_int tbb * 1.5))
          in
          info "Sleeping %.2f seconds." secs
          >>= fun () -> System.sleep secs >>= fun () -> continue_or_not ()
      | Some `Call_contract ->
          ( match List.random_element !valid_contracts with
          | None -> info "No valid contracts to call."
          | Some (name, params) ->
              client_cmd
                (Fmt.str "transfer-%s" name)
                ["transfer"; "1"; "from"; from; "to"; name; "--arg"; params]
              >>= fun (success, _) ->
              info "Called %s(%s): %a" name params pp_success success )
          >>= fun () -> continue_or_not ()
      | Some `Add_contract ->
          let name = Fmt.str "contract-%d" iteration in
          let push_drops = Random.int 100 in
          let parameter, init_storage =
            match List.random_element [`Unit; `String] with
            | Some `String ->
                ( "string"
                , Fmt.str "%S"
                    (String.init
                       (Random.int 42 + 1)
                       ~f:(fun _ -> Random.int 20 + 40 |> Char.of_int_exn)) )
            | _ -> ("unit", "Unit") in
          Michelson.prepare_origination_of_id_script state ~name ~from
            ~protocol_kind:protocol.Tezos_protocol.kind ~parameter
            ~init_storage ~push_drops
          >>= fun origination ->
          client_cmd (Fmt.str "originate-%s" name) origination
          >>= fun (success, _) ->
          if success then
            valid_contracts := (name, init_storage) :: !valid_contracts ;
          info "Origination of `%s` (%s : %s): `%a`." name init_storage
            parameter pp_success success
          >>= fun () -> continue_or_not ()
      | Some `Multisig_contract ->
          let num_signers = Random.int 5 + 1 in
          let outer_repeat = Random.int 5 + 1 in
          let contract_repeat = Random.int 5 + 1 in
          Forge.run_multi_sig state client nodes ~num_signers ~outer_repeat
            ~contract_repeat
          >>= fun () -> continue_or_not ()
      | None -> continue_or_not () in
    loop 0
end

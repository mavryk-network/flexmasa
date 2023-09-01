open Internal_pervasives

type t = { name : string; michelson : string }

let parse_origination ~lines name =
  let rec prefix_from_list ~prefix = function
    | [] -> None
    | x :: xs ->
        if not (String.is_prefix x ~prefix) then prefix_from_list ~prefix xs
        else Some x
  in
  let l = List.map lines ~f:String.lstrip in
  match prefix_from_list ~prefix:"KT1" l with
  | None ->
      System_error.fail_fatalf "Failed to parse %s smart contract origination."
        name
  | Some address -> return address

let originate_smart_contract state ~client ~account t =
  Tezos_client.successful_client_cmd state ~client
    [
      "originate";
      "contract";
      t.name;
      "transferring";
      "0";
      "from";
      account;
      "running";
      t.michelson;
      "--burn-cap";
      "15";
    ]
  >>= fun res -> parse_origination ~lines:res#out t.name

let default_contracts ~(smart_rollup : Smart_rollup.t option) =
  let open Default_contracts in
  let tx_kernel_contract =
    (* Origintate the mint_and_deposit_to_rollup contract for the default
       smart-rollup (tx-rollup). *)
    match smart_rollup with
    | None -> []
    | Some rollup -> (
        match rollup.custom_kernel with
        | None ->
            [
              {
                name = "mint_and_deposit_to_rollup";
                michelson = mint_and_deposit_to_rollup;
              };
            ]
        | Some _ -> [])
  in
  tx_kernel_contract @ []

let run state ~keys_and_daemons ~smart_contracts ~smart_rollup =
  let all_contracts = smart_contracts @ default_contracts ~smart_rollup in
  match all_contracts with
  | [] -> return ()
  | _ ->
      let accounts_and_clients =
        List.map keys_and_daemons ~f:(fun (_, a, c, _, _) -> (a, c))
      in
      List_sequential.iteri all_contracts ~f:(fun ith t ->
          let account, client =
            List.nth_exn accounts_and_clients
              (ith % List.length accounts_and_clients)
          in
          originate_smart_contract state ~client
            ~account:(Tezos_protocol.Account.name account)
            t
          >>= fun address ->
          Console.say state
            EF.(
              desc_list
                (haf "Originated smart contract %S" t.name)
                [ desc (af "Address:") (af "%s" address) ]))

let cmdliner_term base_state () =
  let open Cmdliner in
  let open Term in
  let docs =
    Manpage_builder.section base_state ~rank:2 ~name:"SMART CONTRACTS"
  in
  let check_extension path =
    match Stdlib.Filename.extension path with
    | ".tz" -> `Ok path
    | _ -> `Error (Fmt.str "Invalid file type: %s (expected .tz)" path)
  in
  const (fun paths ->
      List.map paths ~f:(fun path ->
          match check_extension path with
          | `Ok path ->
              let name = Stdlib.Filename.(basename path |> chop_extension) in
              { name; michelson = path }
          | `Error _ -> failwith "Invalid path"))
  $ Arg.(
      value
        (opt_all string []
           (info [ "smart-contract" ]
              ~doc:
                "Provide a `path` for the smart contract. This option can be \
                 used multiple times."
              ~docv:"PATH" ~docs)))

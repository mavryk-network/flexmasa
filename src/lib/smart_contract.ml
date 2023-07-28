open Internal_pervasives

type t = { name : string; michelson : string; init_storage : string }

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
      "--init";
      t.init_storage;
      "--burn-cap";
      "15";
    ]
  >>= fun res -> parse_origination ~lines:res#out t.name

let run state ~keys_and_daemons ~smart_contracts =
  match smart_contracts with
  | [] -> return ()
  | _ ->
      let accounts_and_clients =
        List.map keys_and_daemons ~f:(fun (_, a, c, _, _) -> (a, c))
      in
      List_sequential.iteri smart_contracts ~f:(fun ith t ->
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
    | _ -> `Error (Fmt.str "Invalid file type: %S (expected .tz)" path)
  in
  const (fun s ->
      List.map s ~f:(fun (path, init_storage) ->
          match check_extension path with
          | `Ok path ->
              let name = Stdlib.Filename.(basename path |> chop_extension) in
              { name; michelson = path; init_storage }
          | `Error s -> failwith s))
  $ Arg.(
      value
        (opt_all
           (pair ~sep:':' string string)
           []
           (info [ "smart-contract" ]
              ~doc:
                "Provide a `path` and `initial storage` for a smart contract. \
                 This option can be used multiple times."
              ~docv:"PATH:INIT" ~docs)))

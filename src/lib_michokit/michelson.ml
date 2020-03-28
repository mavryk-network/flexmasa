open Flextesa
open Internal_pervasives
module IFmt = More_fmt

module Concrete = struct
  module Parse_error = struct
    type t = [`Michelson_parsing of string * exn]

    let pp ppf (`Michelson_parsing (code, ex)) =
      let open IFmt in
      wrapping_box ~indent:2 ppf (fun ppf ->
          pf ppf "Michelson-parsing-error:" ;
          sp ppf () ;
          long_string ppf code ;
          sp ppf () ;
          string ppf "->" ;
          sp ppf () ;
          exn ppf ex)

    let fail s e = fail (`Michelson_parsing (s, e))
  end

  let parse s =
    try
      Tezos_client_alpha.Michelson_v1_parser.(
        (parse_toplevel s |> fst).expanded)
      |> return
    with e -> Parse_error.fail s e

  let to_string e =
    let buf = Buffer.create 1000 in
    let fmt = Caml.Format.formatter_of_buffer buf in
    Tezos_client_alpha.Michelson_v1_printer.print_expr_unwrapped fmt e ;
    Caml.Format.pp_print_flush fmt () ;
    Buffer.contents buf
end

module Tz_protocol = Tezos_protocol_alpha.Protocol

module Transform = struct
  let strip_errors_and_annotations expr =
    let open Tz_protocol.Environment.Micheline in
    let all_failwith_arguments = ref [] in
    let add_failwith_argument arg =
      match
        List.find !all_failwith_arguments ~f:(fun (_, a) -> Poly.equal a arg)
      with
      | Some (id, _) ->
          (* Printf.eprintf "found %d\n%!" id ; *)
          id
      | None ->
          let id = List.length !all_failwith_arguments in
          all_failwith_arguments := (id, arg) :: !all_failwith_arguments ;
          (* Printf.eprintf "not found %d\n%!" id ; *)
          id in
    let rec transform = function
      | (Int _ | String _ | Bytes _) as e -> e
      | Prim (a, b, nl, _ann) -> Prim (a, b, List.map ~f:transform nl, [])
      | Seq (loc, node_list) ->
          let open Tz_protocol.Michelson_v1_primitives in
          let new_node_list =
            match node_list with
            | [ ( Prim
                    ( l1
                    , I_PUSH
                    , (* [Prim (l2, T_string, ns, _anns); String (l3, s)] *)
                    _
                    , _annt ) as anything )
              ; Prim (l4, I_FAILWITH, nf, _annf) ] ->
                (* Caml.Format.eprintf "\n\n\nFound failwith: %S\n%!" s ; *)
                let id = add_failwith_argument (strip_locations anything) in
                [ Prim
                    ( l1
                    , I_PUSH
                    , [ Prim (l1, T_nat, [], [])
                      ; Int (l1, Z.of_int id) (* Prim (l1, D_Unit, [], []) *)
                        (* ; Int (l1, Z.zero) *) ]
                    , [] )
                ; Prim (l4, I_FAILWITH, nf, []) ]
            | nl -> List.map ~f:transform nl in
          Seq (loc, new_node_list) in
    let res_node = transform (root expr) in
    (strip_locations res_node, !all_failwith_arguments)
end

module Json = struct
  let dummy_storage () =
    let open Tz_protocol.Environment.Micheline in
    Seq (0, []) |> strip_locations

  let of_expr expr =
    match
      Data_encoding.Json.construct Tz_protocol.Script_repr.encoding
        Tz_protocol.Script_repr.
          {code= lazy_expr expr; storage= lazy_expr (dummy_storage ())}
    with
    | `O [("code", o); ("storage", _)] -> return (o : Ezjsonm.value)
    | _other -> System_error.fail_fatalf "Error with expr->json: this is a bug"
end

module File_io = struct
  let read_file state input_file =
    match Caml.Filename.extension input_file with
    | ".tz" ->
        System.read_file state input_file
        >>= fun content -> Concrete.parse content
    | other ->
        System_error.fail_fatalf "Cannot parse file with extension %S" other

  let write_file state ~path expr =
    match Caml.Filename.extension path with
    | ".tz" -> System.write_file state path ~content:(Concrete.to_string expr)
    | ".json" ->
        Json.of_expr expr
        >>= fun json ->
        System.write_file state path
          ~content:(Ezjsonm.value_to_string ~minify:false json)
    | other ->
        System_error.fail_fatalf "Don't know what to do with extension %S"
          other
end

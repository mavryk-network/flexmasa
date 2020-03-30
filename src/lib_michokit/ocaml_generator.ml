open Flextesa
open Internal_pervasives
module IFmt = More_fmt

let dbg fmt = Fmt.epr Caml.("ocofmi: " ^^ fmt ^^ "\n%!")
let pp_field_annot ppf (`Field_annot fa) = Fmt.pf ppf "(FA: %s)" fa
let pp_type_annot ppf (`Type_annot fa) = Fmt.pf ppf "(TA: %s)" fa

let rec analyze_type ty =
  let open Tezos_raw_protocol_alpha.Script_ir_translator in
  let open Tezos_raw_protocol_alpha.Script_typed_ir in
  match ty with
  | Ex_ty (Union_t ((l, lann), (r, rann), type_annot, _has_big_map)) ->
      dbg "(union (%a | %a) %a)"
        Fmt.(option pp_field_annot)
        lann
        Fmt.(option pp_field_annot)
        rann
        Fmt.(option pp_type_annot)
        type_annot ;
      analyze_type (Ex_ty l) ;
      analyze_type (Ex_ty r)
  | Ex_ty _ty -> dbg "()"

module Simpler_michelson_type = struct
  open Tezos_raw_protocol_alpha.Script_ir_translator
  open Tezos_raw_protocol_alpha.Script_typed_ir

  module Tree = struct
    type 'a t = Leaf of 'a | Node of 'a t * 'a t

    let leaf x = Leaf x
    let node l r = Node (l, r)

    let rec iter ~f = function
      | Leaf x -> f x
      | Node (l, r) -> iter ~f l ; iter ~f r
  end

  type t =
    | Sum of {variants: field Tree.t; type_annotations: string list}
    | Record of {fields: field Tree.t; type_annotations: string list}
    | List of t
    | Set of t
    | Map of t * t
    | Big_map of t * t
    | Lambda of t * t
    | Unit
    | Int
    | Nat
    | Signature
    | String
    | Bytes
    | Mutez
    | Key_hash
    | Key
    | Timestamp
    | Address
    | Bool
    | Chain_id
    | Operation
    | Contract of t
    | Option of t
    | Unknown of ex_ty

  and field = {tag: string option; content: t}

  let rec pp ppf t =
    let open IFmt in
    match t with
    | Sum {variants; type_annotations} ->
        vertical_box ~indent:4 ppf (fun ppf ->
            pf ppf "Sum[%a]:" (box (list ~sep:comma string)) type_annotations ;
            Tree.iter variants ~f:(fun {tag; content} ->
                cut ppf () ;
                wrapping_box ~indent:4 ppf (fun ppf ->
                    pf ppf "| %a ->@ %a" (option string) tag pp content)))
    | Record {fields; type_annotations} ->
        vertical_box ~indent:4 ppf (fun ppf ->
            pf ppf "Record[%a]:{"
              (box (list ~sep:comma string))
              type_annotations ;
            Tree.iter fields ~f:(fun {tag; content} ->
                cut ppf () ;
                pf ppf "@[%a ->@ %a;@]" (option string) tag pp content) ;
            pf ppf "@,}")
    | List t -> pf ppf "List (%a)" pp t
    | Set t -> pf ppf "Set(%a)" pp t
    | Map (f, t) -> pf ppf "Map(%a->%a)" pp f pp t
    | Big_map (f, t) -> pf ppf "Big_map(%a->%a)" pp f pp t
    | Lambda (f, t) -> pf ppf "Lambda(%a->%a)" pp f pp t
    | Unit -> string ppf "Unit"
    | Int -> string ppf "Int"
    | Nat -> string ppf "Nat"
    | Signature -> string ppf "Signature"
    | String -> string ppf "String"
    | Bytes -> string ppf "Bytes"
    | Mutez -> string ppf "Mutez"
    | Key_hash -> string ppf "Key_hash"
    | Key -> string ppf "Key"
    | Timestamp -> string ppf "Timestamp"
    | Address -> string ppf "Address"
    | Bool -> string ppf "Bool"
    | Chain_id -> string ppf "Chain_id"
    | Operation -> string ppf "Operation"
    | Contract t -> pf ppf "Contract(%a)" pp t
    | Option t -> pf ppf "Option(%a)" pp t
    | Unknown _ -> pf ppf "UNKNOWN"

  let rec of_type : type a. a ty -> t =
   fun ty ->
    match ty with
    | Union_t ((l, lann), (r, rann), type_annot, _has_big_map) ->
        let left = of_type l in
        let right = of_type r in
        let explore v ann =
          match (v, ann) with
          | content, Some (`Field_annot fa) ->
              (Tree.leaf {tag= Some fa; content}, [])
          | Sum {variants; type_annotations}, None ->
              (variants, type_annotations)
          | content, None -> (Tree.leaf {tag= None; content}, []) in
        let vl, tal = explore left lann in
        let rl, tar = explore right rann in
        let variants, type_annotations =
          ( Tree.node vl rl
          , tal
            @ ( match type_annot with
              | Some (`Type_annot ta) -> [ta]
              | None -> [] )
            @ tar ) in
        Sum {variants; type_annotations}
    | Pair_t ((l, lann, lfann), (r, rann, rfann), tao, _has_big_map) ->
        let left = of_type l in
        let right = of_type r in
        List.iter [lfann; rfann] ~f:(fun an ->
            Option.iter an ~f:(fun (`Var_annot va) ->
                dbg "forgetting var-annot: %S" va)) ;
        flatten_record left lann right rann tao
    | List_t (t, type_annot, _has_big_map) ->
        Option.iter type_annot ~f:(fun (`Type_annot ta) ->
            dbg "forggetting type annot: %S" ta) ;
        List (of_type t)
    | Set_t (t, type_annot) ->
        Option.iter type_annot ~f:(fun (`Type_annot ta) ->
            dbg "forggetting type annot: %S" ta) ;
        Set (of_comparable t)
    | Map_t (f, t, type_annot, _) ->
        Option.iter type_annot ~f:(fun (`Type_annot ta) ->
            dbg "forggetting type annot: %S" ta) ;
        Map (of_comparable f, of_type t)
    | Big_map_t (f, t, type_annot) ->
        Option.iter type_annot ~f:(fun (`Type_annot ta) ->
            dbg "forggetting type annot: %S" ta) ;
        Big_map (of_comparable f, of_type t)
    | Unit_t _ -> Unit
    | Int_t _ -> Int
    | Nat_t _ -> Nat
    | Signature_t _ -> Signature
    | String_t _ -> String
    | Bytes_t _ -> Bytes
    | Mutez_t _ -> Mutez
    | Key_hash_t _ -> Key_hash
    | Key_t _ -> Key
    | Timestamp_t _ -> Timestamp
    | Address_t _ -> Address
    | Bool_t _ -> Bool
    | Contract_t (ty, _) -> Contract (of_type ty)
    | Lambda_t (f, t, type_annot) ->
        let ft = of_type f in
        let tt = of_type t in
        Option.iter type_annot ~f:(fun (`Type_annot ta) ->
            dbg "forggetting type annot: %S" ta) ;
        Lambda (ft, tt)
    | Option_t (t, type_annot, _) ->
        Option.iter type_annot ~f:(fun (`Type_annot ta) ->
            dbg "forggetting type annot: %S" ta) ;
        Option (of_type t)
    | Operation_t _ -> Operation
    | Chain_id_t _ -> Chain_id

  and of_comparable : type a b. (a, b) comparable_struct -> t =
   fun cty ->
    match cty with
    | Int_key tao -> of_type (Int_t tao)
    | Nat_key tao -> of_type (Nat_t tao)
    | String_key tao -> of_type (String_t tao)
    | Bytes_key tao -> of_type (Bytes_t tao)
    | Mutez_key tao -> of_type (Mutez_t tao)
    | Bool_key tao -> of_type (Bool_t tao)
    | Key_hash_key tao -> of_type (Key_hash_t tao)
    | Timestamp_key tao -> of_type (Timestamp_t tao)
    | Address_key tao -> of_type (Address_t tao)
    | Pair_key ((l, lann), (r, rann), tao) ->
        let left = of_comparable l in
        let right = of_comparable r in
        flatten_record left lann right rann tao

  and flatten_record left lann right rann type_annot =
    let explore v ann =
      match (v, ann) with
      | content, Some (`Field_annot fa) ->
          (Tree.leaf {tag= Some fa; content}, [])
      | Record {fields; type_annotations}, None -> (fields, type_annotations)
      | content, None -> (Tree.leaf {tag= None; content}, []) in
    let fl, tal = explore left lann in
    let fr, tar = explore right rann in
    let fields, type_annotations =
      ( Tree.node fl fr
      , tal
        @ (match type_annot with Some (`Type_annot ta) -> [ta] | None -> [])
        @ tar ) in
    Record {fields; type_annotations}
end

let make_module expr =
  let open Michelson.Tz_protocol.Environment.Micheline in
  let module Prim = Michelson.Tz_protocol.Michelson_v1_primitives in
  match root expr with
  | Seq (_, Prim (_, Prim.K_parameter, [the_type], _ann) :: _) ->
      Michelson.Typed_ir.parse_type the_type
      >>= fun ex_ty ->
      let simple =
        match ex_ty with Ex_ty ty -> Simpler_michelson_type.of_type ty in
      Michelson.Typed_ir.unparse_type ex_ty
      >>= fun back_to_node ->
      dbg "ocaml:@,%a" Simpler_michelson_type.pp simple ;
      (* Dbg.f (fun f -> f "Found the type: %a" Dbg.pp_any the_type) ; *)
      let first_comment =
        Fmt.str "(* Generated code for\n%a\n*)\n"
          Tezos_client_alpha.Michelson_v1_printer.print_expr_unwrapped
          (strip_locations back_to_node) in
      (* Dbg.f (fun f -> f "Built the type: %a" Dbg.pp_any ty) ; *)
      return first_comment
  | _ -> Fmt.failwith "not here"

module Command = struct
  let run state ~input_file ~output_file () =
    let open Michelson in
    File_io.read_file state input_file
    >>= fun expr ->
    make_module expr
    >>= fun ocaml -> System.write_file state output_file ~content:ocaml

  let make ?(command_name = "ocaml-of-michelson") () =
    let open Cmdliner in
    let open Term in
    let pp_error ppf e =
      match e with
      | #System_error.t as e -> System_error.pp ppf e
      | `Michelson_parsing _ as mp -> Michelson.Concrete.Parse_error.pp ppf mp
    in
    Test_command_line.Run_command.make ~pp_error
      ( pure (fun input_file output_file state ->
            (state, run state ~input_file ~output_file))
      $ Arg.(
          required
            (pos 0 (some string) None
               (info [] ~docv:"INPUT-PATH" ~doc:"Input file.")))
      $ Arg.(
          required
            (pos 1 (some string) None
               (info [] ~docv:"OUTPUT-PATH" ~doc:"Output file.")))
      $ Test_command_line.cli_state ~name:"michokit-ocofmi" () )
      (info command_name ~doc:"Generate OCaml code from Michelson.")
end

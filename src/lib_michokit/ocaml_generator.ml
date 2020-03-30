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
  (* open Tezos_raw_protocol_alpha.Script_ir_translator *)
  open Tezos_raw_protocol_alpha.Script_typed_ir

  module Tree = struct
    type 'a t = Leaf of 'a | Node of 'a t * 'a t

    let leaf x = Leaf x
    let node l r = Node (l, r)

    let rec iter ~f = function
      | Leaf x -> f x
      | Node (l, r) -> iter ~f l ; iter ~f r

    let rec to_list = function
      | Leaf x -> [x]
      | Node (l, r) -> to_list l @ to_list r
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

module Ocaml = struct
  type t =
    | Empty
    | Comment of string
    | Module of {name: string; structure: string list}
    | Concat of t list

  let new_module name structure = Module {name; structure}
  let concat l = Concat l
  let append l x = Concat (l @ [x])
  let comment c = Comment c

  let rec to_string = function
    | Empty -> ""
    | Comment c -> Fmt.str "  (* %s *)  " c
    | Module {name; structure} ->
        Fmt.str "module %s = struct %s end" name
          (String.concat ~sep:"\n" structure)
    | Concat l -> String.concat ~sep:" \n " (List.map ~f:to_string l)

  let clean_up o =
    let modules = ref [] in
    let rec go = function
      | Module {name; _} when List.mem !modules name ~equal:String.equal ->
          Comment (Fmt.str "Removed %s (duplicate)" name)
      | Module {name; _} as not_yet ->
          modules := name :: !modules ;
          not_yet
      | Empty | Concat [] -> Empty
      | Comment _ as c -> c
      | Concat t -> Concat (List.map ~f:go t) in
    go o

  module Deriving_option = struct
    type t = {all: string list; records: string list; variants: string list}

    let make ?(records = []) ?(variants = []) all = {all; records; variants}

    let render t what =
      let l =
        match what with
        | `Any -> t.all
        | `Record -> t.all @ t.records
        | `Variant -> t.all @ t.variants in
      match l with
      | [] -> " (* no deriving *) "
      | more -> Fmt.(str "[@@@@deriving %a ]" (list ~sep:comma string)) more

    let default = make ["show"; "eq"] ~records:["make"]
  end

  type options = {deriving: Deriving_option.t}

  let default_options = {deriving= Deriving_option.default}

  let of_simple_type ?(options = default_options) ~intro_blob ~name simple =
    let v s = Fmt.str "%s.t" s in
    let m ?(kind = `Any) ?layout ?(type_def = "unit") ?(type_parameter = "") s
        =
      new_module s
        [ Fmt.str "type %s t = %s %s" type_parameter type_def
            (Deriving_option.render options.deriving kind)
        ; Option.value_map ~default:"(* no layout here *)" layout ~f:(fun s ->
              Fmt.str "let layout () : Pairing_layout.t = %s" s) ] in
    let open Simpler_michelson_type in
    let record_or_variant kind ~fields ~name ~type_def ~typedef_field ~continue
        =
      let modname = String.capitalize name in
      let compiled_fields =
        Tree.to_list fields
        |> List.mapi ~f:(fun idx {tag; content} ->
               let name =
                 Option.value_map tag ~f:String.capitalize
                   ~default:(Fmt.str "%s_%d" modname idx) in
               (String.uncapitalize name, continue ~name content)) in
      let type_def =
        type_def
          ( List.map compiled_fields ~f:(fun (field_name, (value, _)) ->
                typedef_field field_name value)
          |> String.concat ~sep:"  " ) in
      let deps = List.map compiled_fields ~f:(fun (_, (_, m)) -> m) in
      let layout =
        let open Tree in
        let rec make = function
          | Leaf _ -> "`V"
          | Node (l, r) -> Fmt.str "(`P (%s, %s))" (make l) (make r) in
        make fields in
      let v = v modname in
      let m = m modname ~kind ~type_def ~layout in
      (v, append deps m) in
    let one_param ~name ~continue ~implementation what elt_t =
      let name = Fmt.str "%s_element" name in
      let velt, melt = continue ~name elt_t in
      let type_def =
        match implementation with `List -> "'a list" | `Option -> "'a option"
      in
      let m = m ~type_def ~type_parameter:"'a" what in
      (Fmt.str "%s %s.t" velt what, concat [melt; m]) in
    let map_or_big_map ~key_t ~elt_t ~name ~continue what =
      let kname = Fmt.str "%s_key" name in
      let ename = Fmt.str "%s_element" name in
      let vk, mk = continue ~name:kname key_t in
      let ve, me = continue ~name:ename elt_t in
      let m = m ~type_def:"('k * 'v) list" ~type_parameter:"('k, 'v)" what in
      (Fmt.str "(%s, %s) %s.t" vk ve what, concat [mk; me; m]) in
    let rec go ~name simple =
      let continue = go in
      let single s = (v s, m s) in
      match simple with
      | Unit -> single "M_unit"
      | Int -> single "M_int"
      | Nat -> single "N_nat"
      | Signature -> single "M_signature"
      | String -> single "M_string"
      | Bytes -> single "M_bytes"
      | Mutez -> single "M_mutez"
      | Key_hash -> single "M_key_hash"
      | Key -> single "M_key"
      | Timestamp -> single "M_timestamp"
      | Address -> single "M_address"
      | Bool -> single "M_bool"
      | Chain_id -> single "M_chain_id"
      | Operation -> single "M_operation"
      | Record {fields; type_annotations= _} ->
          record_or_variant `Record ~fields ~name
            ~typedef_field:(fun f v ->
              Fmt.str "%s : %s;" (String.uncapitalize f) v)
            ~continue ~type_def:(Fmt.str "{ %s }")
      | Sum {variants; type_annotations= _} ->
          record_or_variant `Variant ~fields:variants ~name
            ~typedef_field:(fun f v ->
              Fmt.str "| %s of %s" (String.capitalize f) v)
            ~continue ~type_def:(Fmt.str " %s ")
      | Set elt_t ->
          one_param ~implementation:`List ~name ~continue "M_set" elt_t
      | List elt_t ->
          one_param ~implementation:`List ~name ~continue "M_list" elt_t
      | Option elt_t ->
          one_param ~implementation:`Option ~name ~continue "M_option" elt_t
      | Contract elt_t ->
          one_param ~implementation:`Option ~name ~continue "M_contract" elt_t
      | Map (key_t, elt_t) ->
          map_or_big_map ~key_t ~elt_t ~name ~continue "M_map"
      | Big_map (key_t, elt_t) ->
          map_or_big_map ~key_t ~elt_t ~name ~continue "M_big_map"
      | Lambda (_, _) -> single "M_lambdas_to_do" in
    let _, s = go ~name simple in
    concat
      [ comment intro_blob
      ; m "Pairing_layout" ~type_def:"[ `P of t * t | `V ]"
      ; s ]
end

let make_module expr =
  let open Michelson.Tz_protocol.Environment.Micheline in
  let module Prim = Michelson.Tz_protocol.Michelson_v1_primitives in
  let handle_type name mich =
    Michelson.Typed_ir.parse_type mich
    >>= fun ex_ty ->
    let simple =
      match ex_ty with Ex_ty ty -> Simpler_michelson_type.of_type ty in
    Michelson.Typed_ir.unparse_type ex_ty
    >>= fun back_to_node ->
    dbg "%s:@,%a" name Simpler_michelson_type.pp simple ;
    (* Dbg.f (fun f -> f "Found the type: %a" Dbg.pp_any the_type) ; *)
    let first_comment =
      Fmt.str "(* Generated code for\n%a\n*)\n"
        Tezos_client_alpha.Michelson_v1_printer.print_expr_unwrapped
        (strip_locations back_to_node) in
    (* Dbg.f (fun f -> f "Built the type: %a" Dbg.pp_any ty) ; *)
    return (Ocaml.of_simple_type ~intro_blob:first_comment ~name simple) in
  let rec find_all acc = function
    | Seq (loc, Prim (_, Prim.K_parameter, [the_type], _ann) :: more) ->
        handle_type "Parameter" the_type
        >>= fun found -> find_all (found :: acc) (Seq (loc, more))
    | Seq (loc, Prim (_, Prim.K_storage, [the_type], _ann) :: more) ->
        handle_type "Storage" the_type
        >>= fun found -> find_all (found :: acc) (Seq (loc, more))
    | maybe_a_type ->
        Asynchronous_result.bind_on_result
          (handle_type "Toplevel" maybe_a_type) ~f:(function
          | Ok o -> return (o :: acc)
          | Error _ -> return acc) in
  find_all [] (root expr) >>= fun l -> return (Ocaml.concat l)

module Command = struct
  let run state ~input_file ~output_file () =
    let open Michelson in
    File_io.read_file state input_file
    >>= fun expr ->
    make_module expr
    >>= fun ocaml ->
    let content = Ocaml.(clean_up ocaml |> to_string) in
    System.write_file state output_file ~content

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

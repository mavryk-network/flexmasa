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

    let mapi t ~f =
      let c = ref 0 in
      let rec fo = function
        | Leaf x ->
            let y = f !c x in
            Caml.incr c ; Leaf y
        | Node (l, r) -> Node (fo l, fo r) in
      fo t
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

    let cmdliner_term () : t Cmdliner.Term.t =
      let open Cmdliner in
      let open Term in
      let make_opt name defaults kind =
        Arg.(
          value
            (opt (list ~sep:',' string) defaults
               (info [name]
                  ~doc:
                    (Fmt.str "Add [@@deriving ..] attributes to %s types." kind))))
      in
      pure (fun all records variants -> make all ~records ~variants)
      $ make_opt "deriving-all" ["show"; "eq"] "all"
      $ make_opt "deriving-records" ["make"] "record"
      $ make_opt "deriving-variants" [] "variant"
  end

  module Options = struct
    type t = {deriving: Deriving_option.t; integers: [`Zarith | `Big_int] list}

    let defaults = {deriving= Deriving_option.default; integers= [`Big_int]}

    let cmdliner_term () =
      let open Cmdliner in
      let open Term in
      pure (fun deriving integers -> {deriving; integers})
      $ Deriving_option.cmdliner_term ()
      $ Arg.(
          value
            (opt
               (list ~sep:','
                  (enum [("zarith", `Zarith); ("bigint", `Big_int)]))
               [`Big_int]
               (info ["integer-types"]
                  ~doc:
                    "Chose which kind of integers to use for int|nat literals \
                     (on top of `int`)")))
  end

  module Type = struct
    type t = T_in_module of string | Apply_1 of t * t | Apply_2 of t * (t * t)

    let t0 s = T_in_module s
    let call_1 s t = Apply_1 (t0 s, t)
    let call_2 s a b = Apply_2 (t0 s, (a, b))

    let rec make_function_call t f =
      match t with
      | T_in_module s -> Fmt.str "%s.%s" s f
      | Apply_1 (tf, arg) ->
          Fmt.str "(%s %s)" (make_function_call tf f)
            (make_function_call arg f)
      | Apply_2 (tf, (arg1, arg2)) ->
          Fmt.str "(%s %s %s)" (make_function_call tf f)
            (make_function_call arg1 f)
            (make_function_call arg2 f)

    let rec make_type_t t =
      match t with
      | T_in_module s -> Fmt.str "%s.t" s
      | Apply_1 (tf, arg) -> Fmt.str "%s %s" (make_type_t arg) (make_type_t tf)
      | Apply_2 (tf, (arg1, arg2)) ->
          Fmt.str "(%s, %s) %s" (make_type_t arg1) (make_type_t arg2)
            (make_type_t tf)
  end

  let of_simple_type ?(options = Options.defaults) ~intro_blob ~name simple =
    let m ?(prelude = "") ?(kind = `Any) ?layout ?(type_def = "unit")
        ?to_concrete ?(type_parameter = "") s =
      new_module s
        [ prelude
        ; Fmt.str "type %s t = %s %s" type_parameter type_def
            (Deriving_option.render options.deriving kind)
        ; Option.value_map ~default:"(* no layout here *)" layout ~f:(fun s ->
              Fmt.str "let layout () : Pairing_layout.t = %s" s)
        ; ( match to_concrete with
          | None -> Fmt.str " (* No to_concrete function *) "
          | Some (t, f) -> Fmt.str "let to_concrete : %s = (%s)" t f ) ] in
    let open Simpler_michelson_type in
    let record_or_variant kind ~fields ~name ~type_def ~typedef_field ~continue
        =
      let modname = String.capitalize name in
      let modname_of_tag idx tag =
        Option.value_map tag ~f:String.capitalize
          ~default:(Fmt.str "%s_%d" modname idx) in
      let compiled_fields =
        Tree.mapi fields ~f:(fun idx {tag; content} ->
            let name = modname_of_tag idx tag in
            (String.uncapitalize name, continue ~name content)) in
      let compiled_fields_list = Tree.to_list compiled_fields in
      let type_def =
        type_def
          ( List.map compiled_fields_list ~f:(fun (field_name, (typ, _)) ->
                typedef_field field_name (typ : Type.t))
          |> String.concat ~sep:"  " ) in
      let to_concrete =
        let t = "t -> string" in
        let f =
          Fmt.str "fun x -> %s"
            ( match kind with
            | `Any -> assert false
            | `Variant ->
                let open Tree in
                let rec make acc = function
                  | Leaf (name, (t, _)) ->
                      let call =
                        Type.make_function_call t "to_concrete" ^ " x" in
                      let sprintf lr x =
                        Fmt.str "(Printf.sprintf \"(%s %%s)\" (%s))" lr x in
                      let rec left_right = function
                        | [] -> call
                        | `L :: more -> sprintf "Left" (left_right more)
                        | `R :: more -> sprintf "Right" (left_right more) in
                      Fmt.str "| %s x -> (%s)" (String.capitalize name)
                        (left_right (List.rev acc))
                  | Node (l, r) -> make (`L :: acc) l ^ make (`R :: acc) r
                in
                Fmt.str "match x with %s" (make [] compiled_fields)
            | `Record ->
                let open Tree in
                let rec make = function
                  | Leaf (name, (t, _)) ->
                      Fmt.str "(%s x.%s)"
                        (Type.make_function_call t "to_concrete")
                        name
                  | Node (l, r) ->
                      Fmt.str "(Printf.sprintf \"(Pair %%s %%s)\" %s %s)"
                        (make l) (make r) in
                make compiled_fields ) in
        (t, f) in
      let deps = List.map compiled_fields_list ~f:(fun (_, (_, m)) -> m) in
      let layout =
        let open Tree in
        let rec make = function
          | Leaf _ -> "`V"
          | Node (l, r) -> Fmt.str "(`P (%s, %s))" (make l) (make r) in
        make fields in
      let v = Type.t0 modname in
      let m = m modname ~kind ~type_def ~layout ~to_concrete in
      (v, append deps m) in
    let one_param ~name ~continue ~implementation what elt_t =
      let name = Fmt.str "%s_element" name in
      let velt, melt = continue ~name elt_t in
      let type_def =
        match implementation with `List -> "'a list" | `Option -> "'a option"
      in
      let to_concrete =
        let t = "('a -> string) -> 'a t -> string" in
        let f =
          let pre = "fun f x -> " in
          pre
          ^
          match implementation with
          | `List ->
              "\"{ \" ^ StringLabels.concat ~sep:\" ; \" (ListLabels.map ~f \
               x) ^ \"}\""
          | `Option ->
              "(match x with None -> \"None\" | Some v -> \"Some \" ^ f v)"
        in
        (t, f) in
      let m = m ~type_def ~type_parameter:"'a" what ~to_concrete in
      ( Type.call_1 what velt (* Fmt.str "%s %s.t" velt what *)
      , concat [melt; m] ) in
    let map_or_big_map ~key_t ~elt_t ~name ~continue what =
      let kname = Fmt.str "%s_key" name in
      let ename = Fmt.str "%s_element" name in
      let vk, mk = continue ~name:kname key_t in
      let ve, me = continue ~name:ename elt_t in
      let to_concrete =
        let t = "('a -> string) -> ('b -> string) -> ('a, 'b) t -> string" in
        let f =
          let pre = "fun fk fv x -> " in
          pre ^ "let f (k, v) = Printf.sprintf \"Elt %s %s\" (fk k) (fv v) in "
          ^ "\"{ \" ^ StringLabels.concat ~sep:\";\" (ListLabels.map ~f x) ^ \
             \"}\"" in
        (t, f) in
      let m =
        m ~type_def:"('k * 'v) list" ~to_concrete ~type_parameter:"('k, 'v)"
          what in
      (Type.call_2 what vk ve, concat [mk; me; m]) in
    let single ?type_def ?to_concrete s =
      (Type.t0 s, m ?to_concrete ?type_def s) in
    let variant_0_arg tag as_string = `V0 (tag, as_string) in
    let variant_1_arg tag typ to_string = `V1 (tag, typ, to_string) in
    let make_variant_implementation variant =
      let type_def =
        List.map variant ~f:(function
          | `V1 (k, v, _) -> Fmt.str "%s of %s" k v
          | `V0 (t, _) -> t)
        |> String.concat ~sep:"\n| " in
      let to_concrete =
        let pattern =
          (* Printf.sprintf "%%S"  *)
          List.map variant ~f:(function
            | `V1 (k, _, f) -> Fmt.str " %s x -> ((%s) x)" k f
            | `V0 (t, s) -> Fmt.str "%s -> %s" t s)
          |> String.concat ~sep:"\n| " in
        ("t -> string", Fmt.str "function %s" pattern) in
      (type_def, to_concrete) in
    let quote_string = "Printf.sprintf \"%S\"" in
    let crypto_thing_implementation modname =
      let crypto_thing_implementation_variant =
        [ variant_1_arg "Raw_b58" "string" quote_string
        ; variant_1_arg "Raw_hex_bytes" "string" "fun x -> x" ] in
      let type_def, to_concrete =
        make_variant_implementation crypto_thing_implementation_variant in
      single modname ~type_def ~to_concrete in
    let int_implementation modname =
      let int_implementation_variant =
        [variant_1_arg "Int" "int" "string_of_int"]
        @ List.map options.integers ~f:(function
            | `Big_int ->
                variant_1_arg "Big_int" "Big_int.t" "Big_int.string_of_big_int"
            | `Zarith -> variant_1_arg "Z" "Z.t" "Z.to_string") in
      let type_def, to_concrete =
        make_variant_implementation int_implementation_variant in
      single modname ~type_def ~to_concrete in
    let string_implementation modname =
      let crypto_thing_implementation_variant =
        [ variant_1_arg "Raw_string" "string" quote_string
        ; variant_1_arg "Raw_hex_bytes" "string" "fun x -> x" ] in
      let type_def, to_concrete =
        make_variant_implementation crypto_thing_implementation_variant in
      single modname ~type_def ~to_concrete in
    let rec go ~name simple =
      let continue = go in
      match simple with
      | Unit ->
          let type_def, to_concrete =
            make_variant_implementation [variant_0_arg "Unit" "\"Unit\""] in
          single "M_unit" ~type_def ~to_concrete
      | Int -> int_implementation "M_int"
      | Nat -> int_implementation "M_nat"
      | Signature -> crypto_thing_implementation "M_signature"
      | String -> string_implementation "M_string"
      | Bytes -> string_implementation "M_bytes"
      | Mutez -> int_implementation "M_mutez"
      | Key_hash -> crypto_thing_implementation "M_key_hash"
      | Key -> crypto_thing_implementation "M_key"
      | Timestamp ->
          let type_def, to_concrete =
            make_variant_implementation
              [ variant_1_arg "Raw_string" "string" quote_string
              ; variant_1_arg "Raw_int" "int" "string_of_int" ] in
          single "M_timestamp" ~type_def ~to_concrete
      | Address -> crypto_thing_implementation "M_address"
      | Bool ->
          let type_def, to_concrete =
            make_variant_implementation
              [ variant_0_arg "True" "\"True\""
              ; variant_0_arg "False" "\"False\"" ] in
          single "M_bool" ~type_def ~to_concrete
      | Chain_id -> crypto_thing_implementation "M_chain_id"
      | Operation ->
          single "M_operation" ~type_def:" | (* impossible to create *) "
      | Record {fields; type_annotations= _} ->
          record_or_variant `Record ~fields ~name
            ~typedef_field:(fun f v ->
              Fmt.str "%s : %s;" (String.uncapitalize f) (Type.make_type_t v))
            ~continue ~type_def:(Fmt.str "{ %s }")
      | Sum {variants; type_annotations= _} ->
          record_or_variant `Variant ~fields:variants ~name
            ~typedef_field:(fun f v ->
              Fmt.str "| %s of %s" (String.capitalize f) (Type.make_type_t v))
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
      ; concat
          (List.map options.integers ~f:(function
            | `Zarith -> comment "ZArith : TODO"
            | `Big_int ->
                (* Big_int. *)
                m "Big_int" ~type_def:"big_int"
                  ~prelude:
                    "include Big_int\n\
                     let equal_big_int = eq_big_int\n\
                    \                     let pp_big_int ppf bi =\n\
                     Format.pp_print_string ppf (string_of_big_int bi)"))
      ; m "Pairing_layout" ~type_def:"[ `P of t * t | `V ]"
      ; s ]
end

let make_module ~options expr =
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
      Fmt.str "Generated code for\n%a\n\n"
        Tezos_client_alpha.Michelson_v1_printer.print_expr_unwrapped
        (strip_locations back_to_node) in
    (* Dbg.f (fun f -> f "Built the type: %a" Dbg.pp_any ty) ; *)
    return
      (Ocaml.of_simple_type ~options ~intro_blob:first_comment ~name simple)
  in
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
  let run state ~options ~input_file ~output_file () =
    let open Michelson in
    File_io.read_file state input_file
    >>= fun expr ->
    make_module expr ~options
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
      ( pure (fun options input_file output_file state ->
            (state, run state ~options ~input_file ~output_file))
      $ Ocaml.Options.cmdliner_term ()
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

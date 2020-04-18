open Flextesa
open Internal_pervasives
module IFmt = More_fmt

let dbg fmt =
  let ppf =
    let noop = Caml.Format.make_formatter (fun _ _ _ -> ()) (fun () -> ()) in
    match Caml.Sys.getenv "ocofmi_debug" with
    | "true" -> Caml.Format.err_formatter
    | _ -> noop
    | exception _ -> noop in
  Fmt.pf ppf Caml.("ocofmi: " ^^ fmt ^^ "\n%!")

(*
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
 *)

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

  module Function = struct
    type t = {name: string; signature: string; body: string; doc: string option}

    let make ?doc ~name (signature, body) = {name; doc; signature; body}

    let render t =
      Fmt.str "%s\nlet %s : %s = (%s)"
        (Option.value_map ~default:"" t.doc ~f:(Fmt.str "\n(** %s *)"))
        t.name t.signature t.body
  end

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

    let libraries t =
      List.dedup_and_sort
        (t.all @ t.records @ t.variants)
        ~compare:String.compare
      |> List.map ~f:(function
           | ("show" | "eq" | "make" | "ord" | "iter" | "fold" | "enum" | "map")
             as d ->
               Fmt.str "ppx_deriving.%s" d
           | "sexp" -> "ppx_sexp_conv"
           | other -> other)
  end

  module Options = struct
    type t = {deriving: Deriving_option.t; integers: [`Zarith | `Big_int] list}

    let defaults = {deriving= Deriving_option.default; integers= [`Big_int]}

    let to_dune_library t ~name =
      let preprocess =
        Deriving_option.libraries t.deriving |> String.concat ~sep:" " in
      let libraries =
        List.map t.integers ~f:(function
          | `Big_int -> "num"
          | `Zarith -> "zarith")
        |> String.concat ~sep:" " in
      Fmt.str "(library (name %s) (preprocess (pps %s)) (libraries %s))" name
        preprocess libraries

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

  (** Constructors for use {i only} by {!of_simple_type}. *)
  module Construct (O : sig
    val options : Options.t
  end) =
  struct
    open O

    let m ?(other_types = []) ?(prelude = "") ?(kind = `Any) ?layout
        ?(type_def = "unit") ~functions ?(type_parameter = "") s =
      new_module s
        ( [ prelude
          ; Fmt.str "type %s t = %s %s" type_parameter type_def
              (Deriving_option.render options.deriving kind) ]
        @ List.map other_types ~f:(fun s ->
              Fmt.str "%s%s" s (Deriving_option.render options.deriving `Any))
        @ [ Option.value_map ~default:"(* no layout here *)" layout
              ~f:(fun s -> Fmt.str "let layout () : Pairing_layout.t = %s" s)
          ]
        @ List.map functions ~f:Function.render )

    let to_concrete (t, f) =
      Function.make ~name:"to_concrete"
        ~doc:"Convert a value to a string in concrete Michelson syntax." (t, f)

    module Of_json = struct
      let json_value_module =
        m "Json_value"
          ~type_def:
            "[ `A of t list | `Bool of bool | `Float of float | `Null | `O of \
             (string * t) list | `String of string ]"
          ~functions:[]
          ~other_types:["type parse_error = [ `Of_json of string * t ]"]

      let f ?(more_args = []) ~name patterns =
        Function.make ~name:"of_json"
          ~doc:"Parse “micheline” JSON representation."
          ( Fmt.str
              "%sJson_value.t -> (%st, [> Json_value.parse_error ]) result"
              ( List.map more_args ~f:(fun (_, t, _) -> Fmt.str "%s -> " t)
              |> String.concat ~sep:"" )
              ( match more_args with
              | [] -> ""
              | more ->
                  Fmt.str "(%s) "
                    ( List.map more ~f:(fun (p, _, _) -> p)
                    |> String.concat ~sep:", " ) )
          , Fmt.str
              "%sfunction %s | other -> Error (`Of_json (\"wrong json for \
               %s\", other))"
              ( List.map more_args ~f:(fun (_, _, a) -> Fmt.str "fun %s -> " a)
              |> String.concat ~sep:"" )
              (String.concat ~sep:" | " patterns)
              name )

      let parsing_error ?(json = "other") name =
        Fmt.str "(`Of_json (\"%s\", %s))" name json

      let pattern_prim ?args prim =
        Fmt.str "`O ((\"prim\", `String %S) ::%s _)" prim
          ( match args with
          | None -> ""
          | Some patt -> Fmt.str "(\"args\", %s) :: " patt )

      let parse_list_of_elts ~name ~f_elts ~construct_from_list =
        let elts = List.mapi f_elts ~f:(fun i f -> (Fmt.str "elt%d" i, f)) in
        let args =
          Fmt.str "`A [%s]" (String.concat ~sep:"; " (List.map ~f:fst elts))
        in
        let matches =
          List.map elts ~f:(fun (e, f) -> Fmt.str "(%s %s)" f e)
          |> String.concat ~sep:", " in
        let oks =
          List.map elts ~f:(fun (e, _) -> Fmt.str "(Ok %s)" e)
          |> String.concat ~sep:", " in
        let tuple =
          List.map elts ~f:(fun (e, _) -> Fmt.str "%s" e)
          |> String.concat ~sep:", " in
        let err_patterns =
          let nb = List.length elts in
          List.init nb ~f:(fun i ->
              Fmt.str "%s (Error _ as err)%s -> err"
                ( List.init (nb - i - 1) ~f:(fun _ -> "_, ")
                |> String.concat ~sep:"" )
                (List.init i ~f:(fun _ -> ", _") |> String.concat ~sep:""))
          |> String.concat ~sep:" | " in
        Fmt.str
          "`A elts ->\n\
           ListLabels.fold_left elts ~init:(Ok []) ~f:(fun p e ->\n\
           match p, e with\n\
           | Error err, _ -> Error err\n\
           | Ok prev, %s ->\n\
           (match %s with\n\
          \ | %s ->  Ok ((%s) :: prev)\n\
          \ | %s)\n\
           | _, other -> Error %s)\n\
           |> (function\n\
          \     | Ok l -> Ok (%s (List.rev l)) | Error _ as e -> e)"
          (pattern_prim "Elt" ~args) matches oks tuple err_patterns
          (Fmt.kstr parsing_error "element of %s" name)
          construct_from_list

      let try_catch f ~json ~name =
        Fmt.str "(try Ok (%s) with _ -> Error %s)" f (parsing_error ~json name)
    end

    let record_or_variant kind ~fields ~name ~type_def ~typedef_field ~continue
        =
      let open Simpler_michelson_type in
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
          ( List.sort compiled_fields_list ~compare:(fun (fa, _) (fb, _) ->
                String.compare fa fb)
          |> List.map ~f:(fun (field_name, (typ, _)) ->
                 typedef_field field_name (typ : Type.t))
          |> String.concat ~sep:"  " ) in
      let to_concrete_functions =
        let make_default ~body =
          let t = "t -> string" in
          let f = Fmt.str "fun x -> %s" body in
          to_concrete (t, f) in
        match kind with
        | `Any -> []
        | `Variant ->
            let open Tree in
            let rec make entry_point acc = function
              | Leaf (name, (t, _)) ->
                  let call = Type.make_function_call t "to_concrete" ^ " x" in
                  let rec left_right = function
                    | [] -> "%s"
                    | `L :: more -> Fmt.str "(Left %s)" (left_right more)
                    | `R :: more -> Fmt.str "(Right %s)" (left_right more)
                  in
                  Fmt.str "| %s x -> (%s)" (String.capitalize name)
                    ( match List.rev acc with
                    | [] -> call
                    | _ when entry_point ->
                        Fmt.str "(`Name %S, `Literal (%s))" name call
                    | more ->
                        Fmt.str "(Printf.sprintf %S (%s))" (left_right more)
                          call )
              | Node (l, r) ->
                  make entry_point (`L :: acc) l
                  ^ make entry_point (`R :: acc) r in
            let with_match entry_point =
              Fmt.str "match x with %s" (make entry_point [] compiled_fields)
            in
            [ make_default ~body:(with_match false)
            ; Function.make ~name:"to_concrete_entry_point"
                ~doc:
                  "Like {!to_concrete} but assume this variant is defining an \
                   entry point (i.e. forget about the [Left|Right] wrapping)."
                ( "t -> ( [ `Name of string ] * [ `Literal of string ])"
                , "fun x -> " ^ with_match true ) ]
        | `Record ->
            let open Tree in
            let rec make = function
              | Leaf (name, (t, _)) ->
                  Fmt.str "(%s x.%s)"
                    (Type.make_function_call t "to_concrete")
                    name
              | Node (l, r) ->
                  Fmt.str "(Printf.sprintf \"(Pair %%s %%s)\" %s %s)" (make l)
                    (make r) in
            [make_default ~body:(make compiled_fields)] in
      let of_json =
        let patterns =
          match kind with
          | `Any -> []
          | `Variant ->
              let open Tree in
              let patts = ref [] in
              let rec make acc = function
                | Leaf (name, (t, _)) ->
                    let esc_name = Fmt.str "%s_v" name in
                    patts :=
                      Fmt.str "%s -> (%s %s) >>= fun %s -> Ok (%s %s)"
                        (List.fold acc ~init:esc_name
                           ~f:(fun prev left_right ->
                             let args = Fmt.str "`A [%s]" prev in
                             Of_json.pattern_prim left_right ~args))
                        (Type.make_function_call t "of_json")
                        esc_name esc_name (String.capitalize name) esc_name
                      :: !patts
                | Node (l, r) ->
                    make ("Left" :: acc) l ;
                    make ("Right" :: acc) r in
              make [] compiled_fields ; !patts
          | `Record ->
              let open Tree in
              let rec make = function
                | Leaf (name, (t, _)) ->
                    ( name
                    , Fmt.str "(%s %s) >>= fun %s ->"
                        (Type.make_function_call t "of_json")
                        name name
                    , name )
                | Node (l, r) ->
                    let lp, lc, lf = make l in
                    let rp, rc, rf = make r in
                    let args = Fmt.str "`A [%s ; %s]" lp rp in
                    ( Of_json.pattern_prim "Pair" ~args
                    , Fmt.str "%s\n%s" lc rc
                    , Fmt.str "%s ; %s" lf rf ) in
              let patt, monad_chain, record_fields = make compiled_fields in
              [Fmt.str "%s ->\n%s\nOk {%s}" patt monad_chain record_fields]
        in
        Of_json.f ~name patterns in
      let deps = List.map compiled_fields_list ~f:(fun (_, (_, m)) -> m) in
      let layout =
        let open Tree in
        let rec make = function
          | Leaf _ -> "`V"
          | Node (l, r) -> Fmt.str "(`P (%s, %s))" (make l) (make r) in
        make fields in
      let v = Type.t0 modname in
      let m =
        m modname ~kind ~type_def ~layout ~prelude:"open! Result_extras"
          ~functions:(to_concrete_functions @ [of_json]) in
      (v, append deps m)

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
              "let f elt = (* hack around micheline's paren-weirdness *)\n\
               let concrete_elt = f elt in\n\
               let lgth = String.length concrete_elt in\n\
               match concrete_elt.[0], concrete_elt.[lgth - 1] with\n\
               | '(', ')' ->\n\
              \   StringLabels.sub concrete_elt ~pos:1 ~len:(lgth - 2)\n\
               | _, _ -> concrete_elt\n\
               in\n\
               \"{ \" ^ StringLabels.concat ~sep:\" ; \" (ListLabels.map ~f \
               x) ^ \"}\""
          | `Option ->
              "(match x with None -> \"None\" | Some v -> \"Some \" ^ f v)"
        in
        to_concrete (t, f) in
      let of_json =
        Of_json.f
          ~more_args:[("'elt", "(Json_value.t -> ('elt, _) result)", "f_elt")]
          ~name
          ( match implementation with
          | `List ->
              [ Of_json.parse_list_of_elts ~name ~f_elts:["f_elt"]
                  ~construct_from_list:"" ]
          | `Option ->
              [ Fmt.str "`O ((\"prim\", `String \"None\") :: _) -> Ok None"
              ; Fmt.str
                  "%s ->\n\
                   (match f_elt one with Ok o -> Ok (Some o) | Error _ as e \
                   -> e)"
                  (Of_json.pattern_prim "Some" ~args:"`A [one]") ] ) in
      let m =
        m ~type_def ~type_parameter:"'a" what ~functions:[to_concrete; of_json]
      in
      ( Type.call_1 what velt (* Fmt.str "%s %s.t" velt what *)
      , concat [melt; m] )

    let map_or_big_map ~key_t ~elt_t ~name ~continue what =
      let kname = Fmt.str "%s_key" name in
      let ename = Fmt.str "%s_element" name in
      let vk, mk = continue ~name:kname key_t in
      let ve, me = continue ~name:ename elt_t in
      let m_name =
        match what with `Map -> "M_map" | `Big_map -> "M_big_map" in
      let type_def =
        let list = "('k * 'v) list" in
        match what with
        | `Map -> list
        | `Big_map -> Fmt.str "List of %s | Int of int" list in
      let to_concrete =
        let t = "('a -> string) -> ('b -> string) -> ('a, 'b) t -> string" in
        let pre = "fun fk fv x -> " in
        let f =
          let deal_with_list =
            "let f (k, v) = Printf.sprintf \"Elt %s %s\" (fk k) (fv v) in "
            ^ "\"{ \" ^ StringLabels.concat ~sep:\";\" (ListLabels.map ~f x) \
               ^ \"}\"" in
          match what with
          | `Map -> pre ^ deal_with_list
          | `Big_map ->
              Fmt.str
                "%smatch x with List x -> (%s) | Int i -> string_of_int i" pre
                deal_with_list in
        to_concrete (t, f) in
      let of_json =
        let patterns =
          let common =
            [ Of_json.parse_list_of_elts ~name ~f_elts:["f_key"; "f_value"]
                ~construct_from_list:
                  (match what with `Map -> "" | `Big_map -> "List ") ] in
          match what with
          | `Map -> common
          | `Big_map ->
              Fmt.str "`O [\"int\", `String i] as j -> %s"
                (Of_json.try_catch "Int (int_of_string i)" ~name:"big-map-int"
                   ~json:"j")
              :: common in
        Of_json.f
          ~more_args:
            [ ("'key", "(Json_value.t -> ('key, _) result)", "f_key")
            ; ("'value", "(Json_value.t -> ('value, _) result)", "f_value") ]
          ~name patterns in
      let m =
        m ~type_def ~functions:[to_concrete; of_json]
          ~type_parameter:"('k, 'v)" m_name in
      (Type.call_2 m_name vk ve, concat [mk; me; m])

    let single ?type_def ~functions s = (Type.t0 s, m ~functions ?type_def s)

    module Micheline_type = struct
      type t = Prim of string | Int of {of_string: string} | String | Bytes

      let int of_string = Int {of_string}
    end

    type variant_implementation =
      | V0 of
          {tag: string; as_concrete_string: string; micheline: Micheline_type.t}
      | V1 of
          { tag: string
          ; argument: string
          ; to_concrete_string: string
          ; micheline: Micheline_type.t option }

    let variant_0_arg tag as_concrete_string micheline =
      V0 {tag; as_concrete_string; micheline}

    let variant_0_self tag =
      variant_0_arg tag (Fmt.str "%S" tag) (Micheline_type.Prim tag)

    let variant_1_arg ?micheline tag argument to_concrete_string =
      V1 {tag; argument; to_concrete_string; micheline}

    let make_variant_implementation modname variant =
      let type_def =
        List.map variant ~f:(function
          | V1 {tag; argument; _} -> Fmt.str "%s of %s" tag argument
          | V0 {tag; _} -> tag)
        |> String.concat ~sep:"\n| " in
      let to_concrete =
        let pattern =
          (* Printf.sprintf "%%S"  *)
          List.map variant ~f:(function
            | V1 {tag= k; to_concrete_string= f; _} ->
                Fmt.str " %s x -> ((%s) x)" k f
            | V0 {tag= t; as_concrete_string= s; _} -> Fmt.str "%s -> %s" t s)
          |> String.concat ~sep:"\n| " in
        to_concrete ("t -> string", Fmt.str "function %s" pattern) in
      let functions =
        let patterns =
          List.concat_map variant ~f:(function
            | V0 {tag; micheline; _} ->
                let patt =
                  match micheline with
                  | Prim s ->
                      let p prefix =
                        Fmt.str "`O (%s(\"prim\" , `String %S) :: _) -> Ok %s"
                          prefix s tag in
                      [p ""; p "_ :: "]
                  | _ -> [] in
                patt
            | V1 {tag; micheline= Some (Int {of_string}); _} ->
                let patt =
                  Fmt.str
                    "`O [\"int\", `String s] as j -> (try Ok (%s (%s s)) with \
                     _ -> Error (`Of_json (\"%s exception for %s\", j))) "
                    tag of_string of_string tag in
                [patt]
            | V1 {tag; micheline= Some String; _} ->
                [Fmt.str "`O [ \"string\", `String s] -> Ok (%s s)" tag]
            | V1 {tag; micheline= Some Bytes; _} ->
                [Fmt.str "`O [ \"bytes\", `String s] -> Ok (%s s)" tag]
            | V1 {micheline= _; _} -> []) in
        [to_concrete; Of_json.f ~name:modname patterns] in
      single modname ~type_def ~functions

    let quote_string = "Printf.sprintf \"%S\""

    let crypto_thing_implementation modname =
      let crypto_thing_implementation_variant =
        [ variant_1_arg "Raw_b58" "string" quote_string
            ~micheline:Micheline_type.String
        ; variant_1_arg "Raw_hex_bytes" "string" "fun x -> x"
            ~micheline:Micheline_type.Bytes ] in
      make_variant_implementation modname crypto_thing_implementation_variant

    let int_implementation modname =
      let int_implementation_variant =
        [ variant_1_arg "Int" "int" "string_of_int"
            ~micheline:(Micheline_type.int "int_of_string") ]
        (* For now only one of the representations can have a micheline. *)
        @ List.map options.integers ~f:(function
            | `Big_int ->
                variant_1_arg "Big_int" "Big_int.t" "Big_int.string_of_big_int"
                (* ~micheline:(Micheline_type.int "Big_int.big_int_of_string") *)
            | `Zarith -> variant_1_arg "Z" "Z.t" "Z.to_string")
        (* ~micheline:(Micheline_type.int "Z.of_string") *) in
      make_variant_implementation modname int_implementation_variant

    let string_implementation modname =
      let crypto_thing_implementation_variant =
        [ variant_1_arg "Raw_string" "string" quote_string
            ~micheline:Micheline_type.String
        ; variant_1_arg "Raw_hex_bytes" "string" "fun x -> x"
            ~micheline:Micheline_type.Bytes ] in
      make_variant_implementation modname crypto_thing_implementation_variant
  end

  let of_simple_type ?(options = Options.defaults) ~intro_blob ~name simple =
    let open Construct (struct
      let options = options
    end) in
    let open Simpler_michelson_type in
    let rec go ~name simple =
      let continue = go in
      match simple with
      | Unit -> make_variant_implementation "M_unit" [variant_0_self "Unit"]
      | Int -> int_implementation "M_int"
      | Nat -> int_implementation "M_nat"
      | Signature -> crypto_thing_implementation "M_signature"
      | String -> string_implementation "M_string"
      | Bytes -> string_implementation "M_bytes"
      | Mutez -> int_implementation "M_mutez"
      | Key_hash -> crypto_thing_implementation "M_key_hash"
      | Key -> crypto_thing_implementation "M_key"
      | Timestamp ->
          make_variant_implementation "M_timestamp"
            [ variant_1_arg "Raw_string" "string" quote_string
            ; variant_1_arg "Raw_int" "int" "string_of_int" ]
      | Address -> crypto_thing_implementation "M_address"
      | Bool ->
          make_variant_implementation "M_bool"
            [variant_0_self "True"; variant_0_self "False"]
      | Chain_id -> crypto_thing_implementation "M_chain_id"
      | Operation ->
          single "M_operation" ~type_def:" | (* impossible to create *) "
            ~functions:[]
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
      | Map (key_t, elt_t) -> map_or_big_map ~key_t ~elt_t ~name ~continue `Map
      | Big_map (key_t, elt_t) ->
          map_or_big_map ~key_t ~elt_t ~name ~continue `Big_map
      | Lambda (_, _) ->
          make_variant_implementation "M_lambda"
            [ variant_1_arg "Concrete_raw_string" "string"
                "Printf.sprintf \"%s\"" ] in
    let _, s = go ~name simple in
    concat
      [ comment intro_blob
      ; concat
          (List.map options.integers ~f:(function
            | `Zarith -> comment "ZArith : TODO"
            | `Big_int ->
                (* Big_int. *)
                m "Big_int" ~type_def:"big_int" ~functions:[]
                  ~prelude:
                    "include Big_int\n\
                     let equal_big_int = eq_big_int\n\
                    \                     let pp_big_int ppf bi =\n\
                     Format.pp_print_string ppf (string_of_big_int bi)"))
      ; m "Pairing_layout" ~type_def:"[ `P of t * t | `V ]" ~functions:[]
      ; new_module "Result_extras"
          ["let (>>=) x f = match x with Ok o -> f o | Error _ as e -> e"]
      ; Of_json.json_value_module; s ]
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
  let run state ~options ~input_file ~output_file ~output_dune () =
    let open Michelson in
    File_io.read_file state input_file
    >>= fun expr ->
    make_module expr ~options
    >>= fun ocaml ->
    let content = Ocaml.(clean_up ocaml |> to_string) in
    System.write_file state output_file ~content
    >>= fun () ->
    match output_dune with
    | None -> return ()
    | Some name ->
        let dune_path = Caml.Filename.(concat (dirname output_file) "dune") in
        let content = Ocaml.Options.to_dune_library options ~name in
        System.write_file state dune_path ~content

  let make ?(command_name = "ocaml-of-michelson") () =
    let open Cmdliner in
    let open Term in
    let pp_error ppf e =
      match e with
      | #System_error.t as e -> System_error.pp ppf e
      | `Michelson_parsing _ as mp -> Michelson.Concrete.Parse_error.pp ppf mp
    in
    Test_command_line.Run_command.make ~pp_error
      ( pure (fun options input_file output_file output_dune state ->
            (state, run state ~options ~input_file ~output_file ~output_dune))
      $ Ocaml.Options.cmdliner_term ()
      $ Arg.(
          required
            (pos 0 (some string) None
               (info [] ~docv:"INPUT-PATH" ~doc:"Input file.")))
      $ Arg.(
          required
            (pos 1 (some string) None
               (info [] ~docv:"OUTPUT-PATH" ~doc:"Output file.")))
      $ Arg.(
          value
            (opt (some string) None
               (info ["output-dune-library"] ~docv:"NAME"
                  ~doc:"Output a `dune` file at next to the output file.")))
      $ Test_command_line.cli_state ~name:"michokit-ocofmi" () )
      (info command_name ~doc:"Generate OCaml code from Michelson.")
end

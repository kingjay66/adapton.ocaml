(** Struct: an experimental alternative to spreadtrees

*)
open Adapton_core
open Primitives
open GrifolaType
module Types = AdaptonTypes
module Statistics = AdaptonStatistics

module type StructType = sig
  module ArtLib : ArtLibType
  module Name : NameType
  module Data : DatType
  module Art : ArtType

  (* 1+R:(a)+D:(d,s)+A:(n,a)+B:(n,a,s)+C:(s) *)
  type 'art art_struct = [ (* articulated struct. *)
  | `Nil
  | `Ready of 'art
  | `Data of Data.t * 'art art_struct
  | `Art of Name.t * 'art
  | `Branch of Name.t * 'art * 'art art_struct
  | `Continue of 'art art_struct   
  ]

  module rec Datastruct : sig
    module Data : DatType
    module Art  : ArtType
  end
    with type Data.t    = Datastruct.Art.t art_struct
    and type Art.Data.t = Datastruct.Art.t art_struct
    and type Art.Name.t = Name.t

end

module type SParamsType = sig
  val max_unarticulated : int
  val min_value_branched : int
end

module MakeCommonStruct
  (ArtLib : ArtLibType)
  (Name   : NameType)
  (Data   : DatType)
  (Params : SParamsType)
  : StructType with type
    ArtLib.lib_id = ArtLib.lib_id
    and  type Name.t = Name.t
    and  type Data.t = Data.t 
=struct
  module ArtLib = ArtLib
  module Name = Name
  module Data = Data
  module Art = ArtLib.MakeArt(Name)(Data)

  type 'art art_struct = [ (* articulated sequence. *)
  | `Nil
  | `Ready of 'art
  | `Data of Data.t * 'art art_struct
  | `Art of Name.t * 'art
  | `Branch of Name.t * 'art * 'art art_struct
    (* constrain `Continue to branches? *)  
  | `Continue of 'art art_struct
  ]

  module rec Datastruct : sig
    module Data : DatType
    module Art  : ArtType
  end
    with type Data.t    = Datastruct.Art.t art_struct
    and type Art.Data.t = Datastruct.Art.t art_struct
    and type Art.Name.t = Name.t
  =struct
    module Data = struct
      type t = Datastruct.Art.t art_struct

      let rec string x =
        match x with
        | `Nil -> "Nil"
        | `Ready(a) -> "Ready("^(Datastruct.Art.string a)^")"
        | `Data(x,xs) -> "Data("^(Data.string x)^","^(string xs)^")"
        | `Art(n,a) -> "Art("^(Name.string n)^","^(Datastruct.Art.string a)^")"
        | `Branch(n,a,xs) -> "Branch("^(Name.string n)^","^(Datastruct.Art.string a)^","^(string xs)^")"
        | `Continue(xs) -> "Continue("^(string xs)^")"

      let rec hash seed x =
        match x with
        | `Nil -> Hashtbl.seeded_hash seed `Nil
        | `Ready(a) -> Datastruct.Art.hash seed a
        | `Data(x,xs) -> Data.hash (hash seed xs) x
        | `Art(n,a) -> Name.hash (Datastruct.Art.hash seed a) n
        | `Branch(n,a,xs) -> Name.hash (Datastruct.Art.hash (hash seed xs) a) n
        | `Continue(xs) -> hash seed xs

      let rec equal xs ys =
        match xs, ys with
        | `Nil, `Nil -> true
        | `Ready(a1), `Ready(a2) -> Datastruct.Art.equal a1 a2
        | `Data(x1,xs1), `Data(x2,xs2) -> Data.equal x1 x2 && equal xs1 xs2
        | `Art(n1,a1), `Art(n2,a2) -> Name.equal n1 n2 && Datastruct.Art.equal a1 a2
        | `Branch(n1,a1,xs1), `Branch(n2,a2,xs2) -> Name.equal n1 n2 && Datastruct.Art.equal a1 a2 && equal xs1 xs2
        | `Continue(xs1), `Continue(xs2) -> equal xs1 xs2
        | _, _ -> false

      let rec sanitize x =
        match x with
        | `Nil -> `Nil
        | `Ready(a) -> `Ready(Datastruct.Art.sanitize a)
        | `Data(x,xs) -> `Data(Data.sanitize x, sanitize xs)
        | `Art(n,a) -> `Art(Name.sanitize n, Datastruct.Art.sanitize a)
        | `Branch(n,a,xs) -> `Branch(Name.sanitize n, Datastruct.Art.sanitize a, sanitize xs)
        | `Continue(xs) -> `Continue(sanitize xs)
    
    end
    module Art = ArtLib.MakeArt(Name)(Data)
  end

(* 
  module AData       = ArtLib.MakeArt(Name)(Data)
  module ADataOption = ArtLib.MakeArt(Name)(Types.Option(Data))
 *)

  (* articulation module for data items *)
  module DArt = Art
  (* articulation module for whole structure *)
  module SArt = Datastruct.Art

  let art_struct_of_valued_list
    ?n:(name = Name.nondet())
    ?max:(max_elm = Params.max_unarticulated)
    ?min:(min_val = Params.min_value_branched)
    (value_of : 'a -> int)
    (data_of : 'a -> Data.t option)
    (input : 'a list)
    : SArt.t
  =
    let name_seed = ref name in
    let next_name () = 
      let ns, n = Name.fork !name_seed in
      name_seed := ns; n
    in
    let rec make_branch br max_val data = 
      match data with
      | [] -> (`Continue(br),[])
      | x::xs ->
        let value = value_of x in
        if value > max_val then
          (* found a higher value, so this branch is over *)
          (`Continue(br),data)
        else if value = max_val || value < min_val then
          (* no reason to branch off *)
          let continue, leftover = make_branch(br)(max_val)(xs) in
          match data_of x with
          | None -> (continue, leftover)
          | Some(x) ->
            (`Data(x, continue), leftover)
        else
          (* create a new branch *)
          let do_branch = lazy (make_branch(inner_branch)(max_val-1)(xs))
          and inner_branch = 
            let branch, _ = Lazy.force do_branch in
            branch
          and leftover =
            let _, rest = Lazy.force do_branch in
            rest
          in
          let outer_branch, rest = make_branch(br)(max_val)(leftover) in
          (`Branch(
              next_name(),
              SArt.cell (next_name()) (inner_branch),
              outer_branch
            ), rest
          )

(*           
          let rec first_result = make_branch(inner_branch)(max_val-1)(xs)
          and inner_branch = 
            let branch, _ = first_result in
            branch
          in
          let _, leftover = first_result in
          let outer_branch, rest = make_branch(br)(max_val)(leftover) in
            (`Branch(
                next_name(),
                SArt.cell (next_name()) (inner_branch),
                outer_branch
              ), rest
            )
 *)
 (*           
          let rec new_branch, leftover =
            let inner_branch, rest = make_branch(new_branch)(max_val-1)(xs) in
            let outer_branch, leftover = make_branch(br)(max_val)(rest) in
            (`Branch(
                next_name(),
                SArt.cell (next_name()) (inner_branch),
                outer_branch
              ), leftover
            )
          in
          (new_branch, leftover)

 *)    
    and main_branch =
      let inner_branch, _ = make_branch(main_branch)(max_int)(input) in
      `Branch(
        next_name(),
        SArt.cell (next_name()) (inner_branch),
        `Nil
      )
    in
    SArt.cell name main_branch

  let more_funs = ()

end

module MakeSequence
  (ArtLib : ArtLibType)
  (Name   : NameType)
  (Data   : DatType)
  (Params : SParamsType)
= struct

  module Common : StructType 
    with type ArtLib.lib_id = ArtLib.lib_id
    and type Name.t = Name.t
    and type Data.t = Data.t 
  = struct
    include (MakeCommonStruct(ArtLib)(Name)(Data)(Params))
  end
  
  module ArtLib = Common.ArtLib
  module Name = Common.Name
  module Data = Common.Data
  module Art = Common.Art
  module SeqData = Common.Datastruct.Data

  type t = Art.t Common.art_struct

  let more_funs = ()

end

(* some old data for reference
  (* ---------- first attempt at mutable list ----------- *)

  (* creates an articulated list *)
  let art_list
    ?g:(granularity=default_granularity)
    (input_list : St.Data.t list)
    : St.List.Data.t
  =
    let rec loop l =
      match l with
      | [] -> `Nil
      | x::xs ->
        if ffs (St.Data.hash 0 x) >= granularity then
          let nm1, nm2 = Name.fork (Name.nondet()) in
          `Cons(x, `Name(nm1, `Art (LArt.cell nm2 (loop xs))))
        else
          `Cons(x, (loop xs))
    in
    loop input_list

  (* returns a standard list *)
  let to_list (list : St.List.Data.t) : St.Data.t list = 
    let rec loop l =
      match l with
      | `Nil -> []
      | `Art(a) -> loop (LArt.force a)
      | `Name(_, xs) -> loop xs
      | `Cons(x, xs) -> x::(loop xs)
    in
    loop list

  (* inserts an element at the beginning of the list *)
  let list_cons
    ?g:(granularity=default_granularity)
    (h : St.Data.t)
    (tl : St.List.Data.t)
  =
    if ffs (St.Data.hash 0 h) >= granularity then
      let nm1, nm2 = Name.fork (Name.nondet()) in
      `Cons(h, `Name(nm1, `Art (LArt.cell nm2 tl)))
    else
      `Cons(h, tl)

  (* returns head and tail of list *)
  let list_snoc
    (list : St.List.Data.t)
    : (St.Data.t * St.List.Data.t) option
  =
    let rec loop l = 
      match l with
      | `Nil -> None
      | `Art(a) -> loop (LArt.force a)
      | `Name(_, xs) -> loop xs
      | `Cons(x, xs) -> Some(x, xs)
    in
    loop list


   (* --------------------------- *) 

  let mut_elms_of_list
    ( name : Name.t )
    ( list : 'a list )
    ( data_of : 'a -> St.Data.t )
    ( name_of : 'a -> Name.t ) 
    ( gran_level : int )
    : St.List.Art.t
  = 
    let rec loop list =
      match list with
      | [] -> `Nil
      | x :: xs ->
        if ffs (St.Data.hash 0 (data_of x)) >= gran_level then
          let nm1, nm2 = Name.fork (name_of x) in
          `Cons((data_of x), `Name(nm1, `Art (St.List.Art.cell nm2 (loop xs))))
        else
          `Cons((data_of x), (loop xs))
    in St.List.Art.cell name (loop list)

  let rec insert_elm list_art h nm_tl_opt =
    match nm_tl_opt with
    | Some (nm, tl_art) ->
      let list_art_content = St.List.Art.force list_art in
      St.List.Art.set list_art (`Cons(h, `Name(nm, `Art(tl_art)))) ;
      St.List.Art.set tl_art list_art_content
    | None ->
      let list_art_content = St.List.Art.force list_art in
      St.List.Art.set list_art (`Cons(h, list_art_content))      

  let rec delete_elm list_art =
    let (x,x_tl) =
      let rec loop list = 
        match list with
        | `Art art ->
          let elm, tl = loop (St.List.Art.force art) in
          elm, (`Art art)
            
        | `Name (nm, tl) ->
          let elm, tl = loop tl in
          elm, (`Name(nm, tl))
            
        | `Cons(x, tl) -> (x,tl)
        | `Nil -> failwith "delete_elm: Nil: No element to delete"
      in
      loop (St.List.Art.force list_art)
    in
    St.List.Art.set list_art x_tl ;
    (x,x_tl)

  let rec next_art x = match x with
    | `Nil -> None
    | `Cons(_, tl) -> next_art tl
    | `Name(_, rest) -> next_art rest
    | `Art a -> Some a

  let rec next_cons x =
    match x with
    | `Nil -> None
    | `Cons(x,xs) -> Some(x,xs)
    | `Art(a) -> next_cons(LArt.force a)
    | `Name(_, xs) -> next_cons xs

  let rec ith_art list count = 
    ( match count with
    | x when x <= 0 -> list
    | _ -> match list with
      | `Nil -> `Nil
      | `Cons(x, xs) -> ith_art xs (count-1)
      | `Name(_, xs) -> ith_art xs count
      | `Art a -> ith_art (St.List.Art.force a) count
    )

  let rec take list count =
    let dec = function
      | Some count -> Some (count-1)
      | None -> None
    in
    ( match count with
    | Some count when (count <= 0) -> []
    | _ ->       
      match list with
      | `Nil -> []
      | `Cons(x, xs) -> x :: (take xs (dec count))
      | `Name(_, xs) -> take xs count
      | `Art a -> take (St.List.Art.force a) count
    )

  let rec list_is_empty ( list : St.List.Data.t) : bool =
    ( match list with
    | `Nil -> true
    | `Cons(_,_) -> false
    | `Art a -> list_is_empty ( LArt.force a )
    | `Name (_,x) -> list_is_empty x
    )

  let list_append = 
    let mfn = LArt.mk_mfn (St.Name.gensym "list_append")
      (module Types.Tuple2(St.List.Data)(St.List.Data))
      (fun r (xs, ys) ->
        let list_append xs ys = r.LArt.mfn_data (xs,ys) in
        ( match xs with
        | `Nil -> ys
        | `Cons(x,tl) -> `Cons(x, list_append tl ys)
        | `Art a -> list_append (LArt.force a) ys
        | `Name(nm,xs) -> 
          let nm1, nm2 = Name.fork nm in
          `Name(nm1, `Art (r.LArt.mfn_nart nm2 (xs, ys)))
        ))
    in
    fun xs ys -> mfn.LArt.mfn_data (xs, ys)

end

*)

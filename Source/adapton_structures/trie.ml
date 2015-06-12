(* Adapted from Pugh POPL '89 *)
open Adapton_core
open Primitives
open GrifolaType

module Useful(D : DatType) = struct
  include D
  let compare : t -> t -> int = Pervasives.compare
end

module type GoodDatType = sig
  include DatType
  val compare : t -> t -> int
end

(* Used to deterministically place elements in a Trie. *)
let _PLACEMENT_SEED = 42

(* this module structure needs work, Grifola is already
   two modules deep. *)
(*module MakeArt = Grifola.Default.ArtLib.MakeArt(Name)*)

(* Bit strings. Type is length * value so bit strings with leading
 * zeros aren't conflated.
 *)
module BS : sig
  include GoodDatType with type t = int * int
  val pow     : int -> int -> int
  val flip    : int -> int -> int
  val is_set  : int -> int -> bool
  val prepend : int -> t -> t
end = struct
  type t = int * int
  let rec equal (lhs0,lhs1) (rhs0,rhs1) =
    ((fun (a : int)  -> fun b  -> a = b) lhs0 rhs0) &&
    ((fun (a : int)  -> fun b  -> a = b) lhs1 rhs1)
  let rec compare (lhs0,lhs1) (rhs0,rhs1) =
    match (fun (a : int)  -> fun b  -> Pervasives.compare a b) lhs0 rhs0
    with
    | (-1)|1 as x -> x
    | _ ->
      (match (fun (a : int)  -> fun b  -> Pervasives.compare a b) lhs1
               rhs1
       with
       | (-1)|1 as x -> x
       | _ -> 0)
  let string (((l, v) as bs) : t) : string =
    if l = 0 then "''"
    else
      let rec loop a = function
        | 0, v -> a
        | l, v -> loop ((if v mod 2 = 0 then "0" else "1")^a) (l-1, v lsr 1) in
      loop "" bs
  let pp fmt s = Format.fprintf fmt "%s" (string s)
  let show = string
  let hash = Hashtbl.seeded_hash
  let sanitize x = x
  
  let rec pow (b : int) : int -> int = function
    | 0 -> 1 | 1 -> b
    | n -> let x = pow b (n / 2) in
           x*x*(if n mod 2 = 0 then 1 else b)

  let flip (i : int) (b : int) : int =
    let n = pow 2 i in 
    (if n land b = n then (-) else (+)) b (pow 2 i)

  let is_set (i : int) (b : int) : bool =
    let n = flip i 0 in n land b = n

  let prepend (b : int) ((l, v) : t) : t = match b with
    | 0 when not (is_set l v) -> (l+1, v)
    | 1 when      is_set l v  -> (l+1, v)
    | 0 | 1 -> (l+1, flip l v)
    | _ -> failwith "b has to be a bit (0 or 1)"

end


module type S = sig
  
  type elt

  module Name : NameType
         
  module rec Data : GoodDatType
         and  Art : ArtType with type Data.t = Data.t
                             and type Name.t = Name.t

  include GoodDatType with type t = Data.t

  val top_name : t -> string
  val empty : ?min_depth:int -> t
  val is_empty : t -> bool
  val force : t -> t
  val singleton : ?min_depth:int -> Name.t -> elt -> t
  val nadd : Name.t -> t -> elt -> t
  val sadd : t -> elt -> t
  val union : t -> t -> t
  val find : (elt -> bool) -> t -> int -> elt option
  val cardinal : t -> int
  val of_list : ?min_depth:int -> Name.t -> elt list -> t
  val to_list : t -> elt list
  val fold : ('a -> elt -> 'a) -> 'a -> t -> 'a
  val structural_fold :
      (module Primitives.DatType with type t = 'a) ->
      ?empty:(BS.t -> 'a -> 'a) ->
       ?atom:(BS.t -> elt -> 'a -> 'a) ->
       ?node:(BS.t -> 'a -> 'a -> 'a) ->
      string -> t -> 'a -> 'a

end

module MakePlace
  (E : sig include GoodDatType val place : t -> int end)
  (Name: NameType)
  (A : ArtLibType)
       : S with type elt = E.t
           and  type Name.t = Name.t = struct

  type elt = E.t

  module Name = Name
  let name_of_data (type d) (module D : DatType with type t = d) (d : d) : Name.t =
    Name.gensym (string_of_int (D.hash (Hashtbl.hash "Trie#name_of_data") d))
               
  module S = struct
    include Set.Make(E)
    let string s =
      let sep = ", " in
      let n, elts = fold (fun x (n, a) -> (n+1, (E.string x)^sep^a)) s (0, "") in
      if n > 0 then
        "{ "^(String.sub elts 0
                ((String.length elts)-(String.length sep)))^" }"
      else "{}"             
    let hash seed s = fold (fun x a -> E.hash a x) s seed
    let pp fmt s = Format.fprintf fmt "%s" (string s)
  end

  type 'art _t =  Node of  BS.t * 'art _t * 'art _t
               |  Atom of  BS.t *  S.t
               | Empty of  BS.t
               |  Root of  int * 'art _t
               |  Name of Name.t * 'art _t
               |   Art of  'art

(*  let rec pp__t poly_art fmt =
    function
    | Node (a0,a1,a2) ->
      (Format.fprintf fmt "@[<hov2>Trie.MakePlace.Node (@,";
       (((BS.pp fmt) a0;
         Format.fprintf fmt ",@ ";
         (pp__t (fun fmt  -> poly_art fmt) fmt) a1);
        Format.fprintf fmt ",@ ";
        (pp__t (fun fmt  -> poly_art fmt) fmt) a2);
       Format.fprintf fmt "@])")
    | Atom (a0,a1) ->
      (Format.fprintf fmt "@[<hov2>Trie.MakePlace.Atom (@,";
       ((BS.pp fmt) a0; Format.fprintf fmt ",@ "; (S.pp fmt) a1);
       Format.fprintf fmt "@])")
    | Empty a0 ->
      (Format.fprintf fmt "(@[<hov2>Trie.MakePlace.Empty@ ";
       (BS.pp fmt) a0;
       Format.fprintf fmt "@])")
    | Root (a0,a1) ->
      (Format.fprintf fmt "@[<hov2>Trie.MakePlace.Root (@,";
       ((Format.fprintf fmt "%d") a0;
        Format.fprintf fmt ",@ ";
        (pp__t (fun fmt  -> poly_art fmt) fmt) a1);
       Format.fprintf fmt "@])")
    | Name (a0,a1) ->
      (Format.fprintf fmt "@[<hov2>Trie.MakePlace.Name (@,";
       (Format.fprintf fmt "%s" (Name.string a0);
        Format.fprintf fmt ",@ ";
        (pp__t (fun fmt  -> poly_art fmt) fmt) a1);
       Format.fprintf fmt "@])")
    | Art a0 ->
      (Format.fprintf fmt "(@[<hov2>Trie.MakePlace.Art@ ";
       (poly_art fmt) a0;
       Format.fprintf fmt "@])")
    and show__t poly_art x = Format.asprintf "%a" (pp__t poly_art) x*)

  let rec compare__t poly_art lhs rhs =
    match (lhs, rhs) with
    | (Node (lhs0,lhs1,lhs2),Node (rhs0,rhs1,rhs2)) ->
      (match BS.compare lhs0 rhs0 with
       | (-1)|1 as x -> x
       | _ ->
         (match (compare__t poly_art) lhs1 rhs1 with
          | (-1)|1 as x -> x
          | _ ->
            (match (compare__t poly_art) lhs2 rhs2 with
             | (-1)|1 as x -> x
             | _ -> 0)))
    | (Atom (lhs0,lhs1),Atom (rhs0,rhs1)) ->
      (match BS.compare lhs0 rhs0 with
       | (-1)|1 as x -> x
       | _ ->
         (match S.compare lhs1 rhs1 with | (-1)|1 as x -> x | _ -> 0))
    | (Empty lhs0,Empty rhs0) ->
      (match BS.compare lhs0 rhs0 with | (-1)|1 as x -> x | _ -> 0)
    | (Root (lhs0,lhs1),Root (rhs0,rhs1)) ->
      (match (fun (a : int)  -> fun b  -> Pervasives.compare a b) lhs0
               rhs0
       with
       | (-1)|1 as x -> x
       | _ ->
         (match (compare__t poly_art) lhs1 rhs1 with
          | (-1)|1 as x -> x
          | _ -> 0))
    | (Name (lhs0,lhs1),Name (rhs0,rhs1)) ->
      (match Name.compare lhs0 rhs0 with
       | (-1)|1 as x -> x
       | _ ->
         (match (compare__t poly_art) lhs1 rhs1 with
          | (-1)|1 as x -> x
          | _ -> 0))
    | (Art lhs0,Art rhs0) ->
      (match poly_art lhs0 rhs0 with | (-1)|1 as x -> x | _ -> 0)
    | _ ->
      let to_int =
        function
        | Node (_,_,_) -> 0
        | Atom (_,_) -> 1
        | Empty _ -> 2
        | Root (_,_) -> 3
        | Name (_,_) -> 4
        | Art _ -> 5 in
      ((fun (a : int)  -> fun b  -> Pervasives.compare a b))
        (to_int lhs) (to_int rhs)

  module rec Data : GoodDatType with type t = Art.t _t = struct

    type t = Art.t _t

    let rec compare = compare__t Art.compare

    let equal = ""
    
    let rec equal t t' = match t, t' with
      | Node (bs, t, u), Node (bs', t', u') ->
        BS.equal bs bs' && equal t t' && equal u u'
      | Atom (bs, es), Atom (bs', es') ->
        (BS.equal bs bs') &&
          (S.for_all (fun e -> S.exists (E.equal e) es') es) &&
          (S.for_all (fun e -> S.exists (E.equal e) es) es')
      | Empty bs, Empty bs' -> BS.equal bs bs'
      | Root (md, t), Root (md', t') ->
        md = md' && equal t t'
      | Art a, Art a' -> Art.equal a a'
      | Name (nm, t), Name (nm', t') ->
        Name.equal nm nm'  && equal t t'
      | _ -> false

    let string : t -> string =
      let rec loop = function
        | Node (bs, t, t') -> (loop t)^" "^(loop t')
        | Atom (bs, es)    ->
          let esstr = S.string es in
          if String.length esstr > 4
          then "\n  "^(BS.string bs)^" "^esstr
          else String.sub esstr 2 ((String.length esstr)-2)
        | Empty bs         -> ""
        | Root (md, t)     -> "{"^(loop t)^"\n}"
        | Name (nm, t)     -> (Name.string nm) ^ ":" ^ (loop t)
        |  Art   a         -> (*loop (Art.force a)*) Art.string a
      in
      loop

    let show = string
    let pp fmt s = Format.fprintf fmt "%s" (string s)

    let hash : int -> t -> int =
      let rec hash (seed : int) : t -> int = function
        | Node (bs, t, t') -> BS.hash (hash (hash seed t') t) bs
        | Atom (bs, es)    -> BS.hash (S.hash seed es) bs
        | Empty bs         -> BS.hash seed bs
        | Root (md, t)     -> Hashtbl.seeded_hash (hash seed t) md
        | Name (nm, t)     -> Name.hash (hash seed t) nm
        |  Art  a          -> Art.hash seed a
      in
      hash

    let rec sanitize = function
      | Node (bs, t, t') -> Node (bs, sanitize t, sanitize t')
      | (Empty _ as t)   -> t
      | Root (md, t)     -> Root (md, sanitize t)
      | Name (nm, t)     -> Name (nm, sanitize t)
      |  Art   a         -> Art (Art.sanitize a)
      | Atom (bs, es)    ->
        let es' = S.fold (fun e -> S.add (E.sanitize e)) es S.empty in
        Atom (bs, es')

  end
  and Art : sig
    include ArtType with type Data.t = Data.t
                     and type Name.t = Name.t
    val compare : t -> t -> int
    val pp : Format.formatter -> t -> unit
    val show : t -> string
  end = struct
    include A.MakeArt(Name)(Data)
    let show = string
    let pp fmt s = Format.fprintf fmt "%s" (show s)
    let compare a a' = compare (hash 42 a) (hash 42 a')
  end

  include Data

  let thunk : Name.t -> t -> t =
    let ident =
      Art.mk_mfn
        (Name.gensym "Trie.MakePlace#thunk")
        (module Data)
        (fun _ t -> t)
    in
    fun nm t -> match t with
    | Name (nm', Art a) when nm' = nm -> t
    | Name (_, Art a) -> failwith "doubled Name node!!!"
    | t ->
      let art = ident.Art.mfn_nart nm t in
      ignore (Art.force art) ;
      Name (nm, Art art)

  let rec is_empty = function
    | Root (_, t) -> is_empty t
    | Art   a     -> is_empty (Art.force a)
    | Name (_, t) -> is_empty t
    | Empty _     -> true
    | _           -> false

  let rec force x = match x with
    | Root (md, t) -> Root (md, force t)
    | Node (bs, t, t') -> Node (bs, force t, force t')
    | Art   a      -> force (Art.force a)
    | Name (_, t)  -> force t
    | Empty _      -> x
    | Atom _       -> x

  let empty : ?min_depth:int -> t =
    fun ?(min_depth=1) ->
      let md = min_depth mod 32 in
      let nm0 = Name.gensym ("Adapton.Trie#empty" ^ (string_of_int md)) in
      let nm1, nm2 = Name.fork nm0 in
      thunk nm1 (Root (md, thunk nm2 (Empty (0, 0))))

  let top_name : t -> string = function
    | Name (nm, _) -> Name.string nm
    | _ -> "not a name"

  let find (pred : elt -> bool) (t : t) (i : int) : elt option =
    let rec loop h = function
      | Empty bs         -> None
      | Node (bs, t, t') -> loop (h lsr 1) (if h mod 2 = 0 then t else t')
      |  Art   a         -> loop h (Art.force a)
      | Atom (bs, es)    ->
        S.fold (fun n -> function None when pred n -> Some n | a -> a) es None
      | Name (_,  t) | Root (_, t) -> loop h t
    in
    loop i t

  let rec fold (f : 'a -> elt -> 'a) (a : 'a) : t -> 'a = function
    | Node (_, t, t') -> fold f (fold f a t) t'
    | Empty _         -> a
    | Atom (_, es)    -> S.fold (fun n a -> f a n) es a
    | Root (_, t)     -> fold f a t
    |  Art  ar        -> fold f a (Art.force ar)
    | Name (_, t)     -> fold f a t

  let structural_fold
      (type o)
      (module Out : DatType with type t = o)
      ?(empty = ((fun bs a   -> a) : BS.t -> o   -> o))
      ?(atom  = ((fun bs e a -> a) : BS.t -> elt -> o -> o))
      ?(node  = ((fun bs a b -> a) : BS.t -> o -> o -> o))
      (namespace : string)
    : t -> o -> o =
    let module IO = A.MakeArt(Name)(Out) in
    let loop = IO.mk_mfn
        (Name.gensym ("Trie.MakeInc#structural_fold#"^namespace))
        (module AdaptonTypes.Tuple2(Out)(Data))
        (fun loop (o, t) -> match t with
           | Node (bs, t, t') -> node bs (loop.IO.mfn_data (o, t)) (loop.IO.mfn_data (o, t'))
           | Empty bs         -> empty bs o
           | Atom (bs, es)    -> S.fold (atom bs) es o
           | Root (_, t)     -> loop.IO.mfn_data (o, t)
           |  Art   a         -> loop.IO.mfn_data (o, Art.force a)
           | Name (nm, t)     ->
             IO.force (loop.IO.mfn_nart nm (o, t)))
    in
    (fun t o -> loop.IO.mfn_data (o, t))

  let cardinal : t -> int =
    let fold =
      structural_fold
        (module Useful(AdaptonTypes.Int))
        ~atom:(fun _ e a -> a+1)
        ~node:(fun _ a b -> a+b)
        "Trie.MakeInc#cardinal" in
    (fun t -> fold t 0)
  
  let rec split_atomic : t -> t =
    let suffix ((l, v) : BS.t) (k : int) : bool = v land k = v in
    function
    | ((Empty _) as t) | ((Node _) as t) -> t
    | Atom (bs, es) ->
      let zerobs = BS.prepend 0 bs in
      let  onebs = BS.prepend 1 bs in
      if suffix onebs (E.place (S.choose es)) (* <-- this choice assumes no hash collisions. *)
      then Node (bs, Empty zerobs, Atom (onebs, es))
      else Node (bs, Atom (zerobs, es), Empty onebs)
    | _ -> assert false
      
  let union : t -> t -> t =
    let loop = Art.mk_mfn
        (Name.gensym "Trie.MakeInc#union")
        (module AdaptonTypes.Tuple2(Data)(Data))
        (fun loop -> function
        | t, t' when equal t t' -> t'
        | Name (nm, Art a), Name (nm', Art a') ->
          let nm'' = Name.pair nm nm' in
          thunk nm'' (loop.Art.mfn_data (Art.force a, Art.force a'))
        | Root (md, t), Root (md', t') when md = md' ->
          Root (md, loop.Art.mfn_data (t, t'))
        | Atom (bs, es), Atom (bs', es')
          (* these choices assume no hash collisions *)
          when E.place (S.choose es) = E.place (S.choose es') ->
          Atom (bs, es')
        | Empty _, t | t, Empty _ -> t
        | t, t' ->
          (match split_atomic t, split_atomic t' with
          | sat, Empty _ | Empty _, sat -> sat
          | Node (bs, zerot, onet), Node (bs', zerot', onet') ->
            Node (bs,
                  loop.Art.mfn_data (zerot, zerot'),
                  loop.Art.mfn_data (onet,  onet'))
          | _ -> assert false (* split atomic only returns Node or Empty *))) in
    (fun t t' -> loop.Art.mfn_data (t, t'))

  let internal_nadd : Name.t -> elt -> BS.t -> int -> t -> t =
    let loop = Art.mk_mfn
        (Name.gensym "Trie.MakePlace#internal_nadd")
        (module AdaptonTypes.Tuple5(Name)(E)(BS)(AdaptonTypes.Int)(Data))
        (fun loop (nm, e, bs, h, t) -> match t with
        | Empty _ -> Atom (bs, S.singleton e)
        | Node (bs, t0, t1) ->
          if h mod 2 = 0
          then
            let t0 = loop.Art.mfn_data (nm, e, (BS.prepend 0 bs), (h lsr 1), t0) in
            Node (bs, t0, t1)
          else               
            let t1 = loop.Art.mfn_data (nm, e, (BS.prepend 1 bs), (h lsr 1), t1) in
            Node (bs, t0, t1)
        | Atom (bs, es) when E.place (S.choose es) = E.place e -> (* <-- assumes no collisions *)
          Atom (bs, S.add e (S.filter (fun e' -> E.place e' <> E.place e) es))
        | Name (_, Art a) ->
          let nm, nm' = Name.fork nm in
          let t = loop.Art.mfn_data (nm', e, bs, h, Art.force a) in
          thunk nm t
        | (Atom _) as t  -> loop.Art.mfn_data (nm, e, bs, h, split_atomic t)
        | t -> assert false)
    in
    fun nm e bs h t -> loop.Art.mfn_data (nm, e, bs, h, t)

  let nadd_deep : Name.t -> int -> t -> elt -> t =
    let loop = Art.mk_mfn
        (Name.gensym "Trie.MakePlace#nadd_deep")
        (module AdaptonTypes.Tuple7(Name)(AdaptonTypes.Int)(E)(BS)(AdaptonTypes.Int)(AdaptonTypes.Int)(Data))
        (fun loop (nm, min, e, bs, h, m, t) -> match t with
           | Empty _ when m = min -> Atom (bs, S.singleton e)
           | t'      when m = min -> internal_nadd nm e bs h t'
           | Empty _ ->
             let nm,  nm'  = Name.fork nm in
             let nm', nm'' = Name.fork nm' in
             if h mod 2 = 0
             then
               let zerobs = BS.prepend 0 bs in
               let t0 = loop.Art.mfn_data (nm'', min, e, zerobs, (h lsr 1), (m+1), (Empty zerobs)) in
               let t1 = Empty (BS.prepend 1 bs) in
               Node (bs, thunk nm t0, thunk nm' t1)
             else
               let onebs = BS.prepend 1 bs in
               let t0 = Empty (BS.prepend 0 bs) in
               let t1 = loop.Art.mfn_data (nm'', min, e, onebs, (h lsr 1), (m+1), (Empty onebs)) in
               Node (bs, thunk nm t0, thunk nm' t1)
           | Node (bs, t0, t1) ->
             if h mod 2 = 0
             then
               let t0 = loop.Art.mfn_data (nm, min, e, (BS.prepend 0 bs), (h lsr 1), (m+1), t0) in
               Node (bs, t0, t1)
             else
               let t1 = loop.Art.mfn_data (nm, min, e, (BS.prepend 1 bs), (h lsr 1), (m+1), t1) in
               Node (bs, t0, t1)
           | Name (_, Art a) -> (* <-- handling in a single case maintains the invariant *)
             let nm, nm' = Name.fork nm in (* that Names always surround Arts  *)
             thunk nm (loop.Art.mfn_data (nm', min, e, bs, h, m, Art.force a))
           | _ -> assert false
         (*| Atom _ -> assert false (* <-- Can't happen unless the minimum depth is violated  *)
           | Root _ -> assert false (* <-- Always unwrap the root in `[n]add`. *)*))
    in
    (fun nm md t e -> loop.Art.mfn_data (nm, md, e, (0, 0), E.place e, 1, t))

  let rec nadd nm t e = match t with
    | Name (_, Art a) -> (match Art.force a with
                          | Root (md, t) ->
                            let nm, nm' = Name.fork nm in
                            let t' = nadd_deep nm' md t e in
                            thunk nm (Root (md, t'))
                          | t -> failwith ("malformed t: " ^ (string t)))
    | Root (md, t) ->
      let nm, nm' = Name.fork nm in
      let t' = nadd_deep nm' md t e in
      thunk nm (Root (md, t'))
    | _ -> assert false (* <-- user code can't hold on to just a Node, Atom, or Empty *)

  let sadd : t -> elt -> t =
    let nm : t * elt -> Name.t =
      name_of_data (module AdaptonTypes.Tuple2(Data)(E))
    in
    fun t e -> nadd (nm (t, e)) t e

  let singleton ?(min_depth = 1) nm (e : elt) : t = nadd nm (empty ~min_depth) e

  let of_list ?(min_depth = 1) nm (l : elt list) : t =
    let out, _ =
      List.fold_left
        (fun (out, nm) e ->
           let nm, nm' = Name.fork nm in
           (nadd nm out e, nm'))
        (empty ~min_depth, nm)
        l
    in
    out

  let to_list : t -> elt list =
    let fold = 
      structural_fold
        (module Useful(AdaptonTypes.List(E)))
        ~atom:(fun _ e a -> e::a)
        ~node:(fun _ a b -> a@b)
        "Trie.Make#to_list" in
    (fun t -> fold t [])

end

module Make(E : GoodDatType) =
  MakePlace(struct include E let place t = hash _PLACEMENT_SEED t end)

module Set = struct

  module type S = sig
    type elt
    module Name : NameType
    module rec Data : GoodDatType
           and  Art : ArtType with type Data.t = Data.t
                               and type Name.t = Name.t
    include GoodDatType with type t = Data.t
    val top_name : t -> string
    val empty : ?min_depth:int -> t
    val is_empty : t -> bool
    val force : t -> t
    val singleton : ?min_depth:int -> Name.t -> elt -> t
    val nadd : Name.t -> t -> elt -> t
    val sadd : t -> elt -> t
    val union : t -> t -> t
    val mem : t -> elt -> bool
    val cardinal : t -> int
    val of_list : ?min_depth:int -> Name.t -> elt list -> t
    val to_list : t -> elt list
    val fold : ('a -> elt -> 'a) -> 'a -> t -> 'a
    val subsumes : ?order:(elt -> elt -> bool) -> t -> t -> bool
    val structural_fold :
      (module DatType with type t = 'a) ->
      ?empty:(BS.t -> 'a -> 'a) ->
       ?atom:(BS.t -> elt -> 'a -> 'a) ->
       ?node:(BS.t -> 'a -> 'a -> 'a) ->
      string -> t -> 'a -> 'a
  end

  module Make(E : GoodDatType)(Name:NameType)(A : ArtLibType) : S
         with type elt = E.t
          and type Name.t = Name.t
                         = struct

    include Make(E)(Name)(A)

    let mem (t : t) : elt -> bool =
      (fun e -> match find (E.equal e) t (E.hash _PLACEMENT_SEED e) with
         | Some _ -> true
         | None   -> false)

    let string t = "set "^(string t)

    let subsumes ?(order = (fun x x' -> E.compare x x' >= 0))
        (t : t) (t' : t) : bool =
      fold
        (fun a x' -> a || fold (fun a x -> a && order x x') a t)
        false
        t'
        
  end

end

module Map = struct

  module type S = sig
    type k
    type v
    module Name : NameType
    module rec Data : GoodDatType
           and  Art : ArtType with type Data.t = Data.t and type Name.t = Name.t
    include GoodDatType with type t = Data.t
    val top_name : t -> string
    val empty : ?min_depth:int -> t
    val force : t -> t
    val singleton : ?min_depth:int -> Name.t -> k -> v -> t
    val nadd : Name.t -> t -> k -> v -> t
    val sadd : t -> k -> v -> t
    val union : t -> t -> t
    val is_empty : t -> bool
    val cardinal : t -> int
    val find : t -> k -> v option
    val mem : t -> k -> bool
    val fold : ('a -> k -> v -> 'a) -> 'a -> t -> 'a
    val structural_fold :
      (module DatType with type t = 'a) ->
      ?empty:(BS.t -> 'a  -> 'a) ->
       ?atom:(BS.t -> k * v -> 'a -> 'a) ->
       ?node:(BS.t -> 'a  -> 'a -> 'a) ->
      string -> t -> 'a -> 'a
    val of_list : ?min_depth:int -> Name.t -> (k * v) list -> t
    val to_list : t -> (k * v) list
  end

  module Make
    (K : GoodDatType)
    (V : GoodDatType)
    (N : NameType)
    (A : ArtLibType)
         : S with type k = K.t
              and type v = V.t
              and type Name.t = N.t = struct 

    let place (k, _) = K.hash _PLACEMENT_SEED k

    include MakePlace
    (struct
      include AdaptonTypes.Tuple2(K)(V)
      let string (k, v) = "["^(K.string k)^" -> "^(V.string v)^"]"
      let pp fmt s = Format.fprintf fmt "%s" (string s)
      let show = string
      let equal (k, v) (k', v') = K.equal k k' && V.equal v v'
      let hash seed (k, v) = K.hash (V.hash seed v) k
      let place = place
      let compare (k, v) (k', v') = Pervasives.compare (K.compare k k') (V.compare v v')
    end)
    (N)
    (A)
        
    type k = K.t
    type v = V.t

    let singleton ?(min_depth = 1) nm (k : k) (v : v) : t = singleton ~min_depth nm (k, v)

    let nadd (n : Name.t) (t : t) (k : k) (v : v) : t = nadd n t (k, v)
    let sadd (t : t) (k : k) (v : v) : t = sadd t (k, v)

    let fold f = fold (fun a (k, v) -> f a k v)

    let find (t : t) : k -> v option =
      (fun k -> match find (fun (k', _) -> K.equal k k') t (K.hash _PLACEMENT_SEED k) with
      | Some (_, v) -> Some v
      | None        -> None)

    let mem (t : t) : k -> bool =
      (fun k -> match find t k with
      | Some _ -> true
      | None   -> false)

  end

end

module Rel = struct

  module type S = sig
    type sv
    module Vs : Set.S with type elt = sv
    include Map.S with type v = Vs.t
    val top_name : t -> string
    val    njoin : Name.t -> t -> k -> sv -> t
    val    sjoin : t -> k -> sv -> t
    val nclobber : Name.t -> t -> k -> sv -> t
    val   branch : ('b -> 'a -> 'b) -> 'b -> t -> k -> (sv -> 'a) -> 'b
    val   svfold : ('a -> k -> sv -> 'a) -> 'a -> t -> 'a
  end

  module Make
    (K : GoodDatType)
    (V : GoodDatType)
    (N : NameType)
    (A : ArtLibType)
    : S with type k = K.t
         and type sv = V.t
         and type Name.t = N.t = struct
    
    type sv = V.t
    module Vs = Set.Make(V)(N)(A)
    module M = Map.Make(K)(Vs)(N)(A)
    include M
    let name_of_data (type d) (module D : DatType with type t = d) (d : d) : Name.t =
      Name.gensym (string_of_int (D.hash (Hashtbl.hash "Trie#name_of_data") d))

    let nclobber : Name.t -> t -> k -> sv -> t =
      fun nm t k v ->
        let nm, nm' = Name.fork nm in
        nadd nm t k (Vs.force (Vs.singleton nm' v))

    let njoin : Name.t -> t -> k -> sv -> t =
      fun nm t k v ->
        let nm, nm' = Name.fork nm in
        let vs' = match find t k with
          | Some vs -> Vs.force (Vs.nadd nm vs v)
          | None    -> Vs.force (Vs.singleton nm v)
        in
        nadd nm' t k vs'

    let sjoin : t -> k -> sv -> t =
      let nm : t * k * sv -> Name.t =
        name_of_data (module AdaptonTypes.Tuple3(M)(K)(V))
      in
      fun t k sv -> njoin (nm (t, k, sv)) t k sv

    let branch
        (type a)
        (type b)
        (add   : (b -> a -> b))
        (empty : b) : t -> k -> (sv -> a) -> b =
      fun t k f ->
        match find t k with
        | None -> empty
        | Some vs -> Vs.fold (fun a n -> add a (f n)) empty vs

    let svfold (type a) (f : a -> k -> sv -> a) : a -> t -> a =
      fold (fun a k -> Vs.fold (fun a v -> f a k v) a)

  end

end


module Graph = struct

  module type S = sig

    type vertex
    include Rel.S with type  k = vertex
                   and type sv = vertex

    val top_name : t -> string
    val mem_vertex : t -> vertex -> bool
    val mem_edge   : t -> vertex -> vertex -> bool
    val nadd_edge : Name.t -> t -> vertex -> vertex -> t
    val to_dot : t -> string
    val fold_edges  : ('a -> vertex -> vertex -> 'a) -> 'a -> t -> 'a
    val fold_vertex : ('a -> vertex -> 'a) -> 'a -> t -> 'a
    val nb_edges  : t -> int
    val nb_vertex : t -> int

  end

  module Make
    (V : GoodDatType)
    (N : NameType)
    (A : ArtLibType)
    : S with type vertex = V.t
         and type Name.t = N.t = struct
    
    type vertex = V.t
    include Rel.Make(V)(V)(N)(A)

    let mem_edge t v v' = match find t v with
      | Some vs -> Vs.fold (fun a v'' -> a || V.equal v' v'') false vs
      | None    -> false

    let mem_vertex = mem
    let nadd_edge nm t v v' =
      if mem_vertex t v'
      then njoin nm t v v'
      else
        let nm, nm' = Name.fork nm in
        njoin nm' (nadd nm t v' (Vs.empty ~min_depth:4)) v v'

    let to_dot _ = failwith "unimplemented"

    let fold_edges  (type a) f a t : a = svfold f a t
    let fold_vertex (type a) f a : t -> a = fold (fun a k _ -> f a k) a

    let nb_vertex = cardinal
    let nb_edges = fold_edges (fun n _ _ -> n+1) 0

    let string_of_list ?(sep=" ") ?(border=(fun s -> "(" ^ s ^ ")")) soe l =
      if List.length l > 0 then
        let elts = List.fold_right (fun elt a -> (soe elt)^sep^a) l "" in
        border (String.sub elts 0 ((String.length elts)-(String.length sep)))
      else border ""

    (*let show t =
      string_of_list
        (fun (v, vs) -> Printf.sprintf "(%s %s)" (V.string v) (Vs.string vs))
        (to_list t)
    let pp ff p = Format.pp_print_string ff (show p)
      let string = show*)

  end

end


(*
module Test  = struct

  open OUnit2

  let unary_tests (type i) (type o)
      ?(printer=(fun _ -> "no printer"))
      ?(eq=(=))
      (nm : string)
      (f : i -> o)
      (l : (i * o) list)
    : test list =
    List.map
      (fun (i, o) ->
         nm >:: (fun ctxt -> assert_equal ~printer ~cmp:eq ~ctxt (f i) o))
      l

  let binary_tests (type i) (type j) (type o)
      ?(printer=(fun _ -> "no printer"))
      ?(eq=(=))
      (nm : string)
      (f : i -> j -> o)
      (l : (i * j * o) list)
    : test list =
    List.map
      (fun (i0, i1, o) ->
         nm >:: (fun ctxt -> assert_equal ~printer ~cmp:eq ~ctxt o (f i0 i1)))
      l

  let nm = Key.nondet

  let bs_suite =
    let pow_tests  =
      binary_tests "pow" BS.pow
        [0, 0, 1;
         42, 0, 1;
         ~-2, 0, 1;
         2, 4, 16;
         ~-2, 3, ~-8] in
    let flip_tests =
      binary_tests "flip" BS.flip
        [0, 0, 1;
         2, 0, 4;
         1, 7, 5;
         3, 7, 15] in
    let is_set_tests =
      binary_tests "is_set" BS.is_set
        [4, 0, false;
         0, 0, false;
         0, 1, true;
         1, 2, true;
         0, 2, false] in
    let prepend_tests =
      binary_tests "prepend" BS.prepend
        [0, (0, 0), (1, 0);
         1, (0, 0), (1, 1);
         1, (1, 1), (2, 3);
         0, (1, 1), (2, 1);
         1, (2, 1), (3, 5)] in
    "bit strings" >::: pow_tests@flip_tests@is_set_tests@prepend_tests

  module S = Set.Make(Useful(AdaptonTypes.String))(Key)(Grifola.Default.ArtLib)

  (*let set_suite =
    let min_depth = 4 in
    let e001 = "a" in
    let e010 = "d" in
    let e010'= "j" in
    let e010''= "gah" in
    let t0   = S.empty ~min_depth in
    let t1   = S.add t0  e001 in
    let t2   = S.add t1  e010 in
    let t3   = S.add t2  e010 in
    let t4   = S.add t3  e010' in
    let t1'  = S.add t0  e001 in
    let t2'  = S.add t1' e010 in
    let t3'  = S.add t2' e010 in
    let t4'  = S.add t3' e010' in
    let t5'  = S.add t4' e010' in
    let t6'  = S.add t5' e010' in
    let cardinal_tests = unary_tests "cardinal" S.cardinal
        [t0, 0; t1, 1; t2, 2; t1', 1; t2', 2; t3, 2; t3', 2; t4, 3; t4', 3] in
    let mem_tests = binary_tests "mem" S.mem
      [t0, e001, false; t0, e010, false;
       t1, e001, true; t1, e010, false;
       t2, e001, true; t2, e010, true; t2, e010', false; t2, e010'', false;
       t3, e001, true; t3, e010, true; t3, e010', false; t3, e010'', false;
       t4, e001, true; t4, e010, true; t4, e010', true; t4', e010'', false;
       t5', e010', true; t6', e010', true] in
    let equal_tests = binary_tests "equal" S.equal
        [t0, t0, true;
         t0, t1, false;
         t1, t1, true;
         t1, t1', true;
         t2, t2', true;
         t4', t4', true;
         t5', t4', true;
         t6', t5', true
        ] in
    let hash_eq_tests = binary_tests "hasheq" (fun x y -> let h = S.hash 42 in h x = h y)
      [t0, t0, true;
       t1, t1', true;
       t2, t2', true;
       t1', t2, false;
       t1', t2, false;
      ] in
    let of_list_tests = unary_tests ~printer:S.string ~eq:S.equal "of_list" (S.of_list ~min_depth)
      [["1"; "2"; "3"], S.add (S.add (S.add t0 "1") "2") "3";
       ["1"; "2"; "3"], S.add (S.add (S.add t0 "3") "2") "1";
       ["3"; "2"; "1"], S.add (S.add (S.add t0 "1") "2") "3";
       ["2"], S.add t0 "2";
       ["1"], S.add t0 "1"] in
    let union_tests = binary_tests ~printer:S.string ~eq:S.equal "union" S.union
      [S.of_list ~min_depth ["1"; "2"; "3"], t0, S.of_list ~min_depth ["1"; "2"; "3"];
       t0, S.of_list ~min_depth ["1"; "2"; "3"], S.of_list ~min_depth ["1"; "2"; "3"];
       (* This is not true for any min depth < 4.
       S.of_list ~min_depth:3 ["1"; "2"; "3"], S.singleton ~min_depth:3 "4",
         S.of_list ~min_depth:3 ["1"; "2"; "3"; "4"]; *)
       S.of_list ~min_depth ["1"; "2"; "3"], S.singleton ~min_depth "4",
         S.of_list ~min_depth ["1"; "2"; "3"; "4"];
       S.of_list ~min_depth:5 ["1"; "2"; "3"], S.singleton ~min_depth:5 "4",
         S.of_list ~min_depth:5 ["1"; "2"; "3"; "4"];
       S.of_list ["one"; "42"; "five-hundred"], S.of_list ["1"; "forty-two"; "500"],
         S.of_list ["one"; "42"; "five-hundred"; "1"; "forty-two"; "500"];
       S.of_list ~min_depth:3 ["1"; "forty-two"; "five-hundred"],
         S.of_list ~min_depth:3 ["1"; "forty-two"; "500"],
         S.of_list ~min_depth:3 ["five-hundred"; "1"; "forty-two"; "500"]] in
    "Set" >::: (cardinal_tests@mem_tests@of_list_tests@union_tests@equal_tests@hash_eq_tests) *)
  let nset_suite =
    let min_depth = 4 in
    let e001 = "a" in
    let e010 = "d" in
    let e010'= "j" in
    let e010''= "gah" in
    let t0   = S.empty ~min_depth in

    let u1 = S.nadd (nm()) t0 e001 in
    let u2 = S.nadd (nm()) u1 e010 in
    let u1a = S.nadd (nm()) t0 e010' in
    let u2a = S.nadd (nm()) t0 e010'' in


    let t1   = S.nadd (nm()) t0  e001 in
    let t2   = S.nadd (nm()) t1  e010 in
    let t3   = S.nadd (nm()) t2  e010 in
    let t4   = S.nadd (nm()) t3  e010' in
    let t1'  = S.nadd (nm()) t0  e001 in
    let t2'  = S.nadd (nm()) t1' e010 in
    let t3'  = S.nadd (nm()) t2' e010 in
    let t4'  = S.nadd (nm()) t3' e010' in
    let t5'  = S.nadd (nm()) t4' e010' in
    let t6'  = S.nadd (nm()) t5' e010' in
    let union_tests = binary_tests ~printer:S.string ~eq:(fun a b -> S.equal (S.force a) (S.force b)) "union" S.union
      [S.of_list ~min_depth (nm()) ["1"; "2"; "3"], t0, S.of_list ~min_depth (nm()) ["1"; "2"; "3"];
       t0, S.of_list ~min_depth (nm()) ["1"; "2"; "3"], S.of_list ~min_depth (nm()) ["1"; "2"; "3"];
       (* This is not true for any min depth < 4.
       S.of_list ~min_depth (nm()):3 ["1"; "2"; "3"], S.singleton ~min_depth:3 "4",
         S.of_list ~min_depth (nm()):3 ["1"; "2"; "3"; "4"]; *)
       S.of_list ~min_depth (nm()) ["1"; "2"; "3"], S.singleton ~min_depth (nm()) "4",
         S.of_list ~min_depth (nm()) ["1"; "2"; "3"; "4"];
       S.of_list ~min_depth:5 (nm()) ["1"; "2"; "3"], S.singleton ~min_depth:5 (nm()) "4",
         S.of_list ~min_depth:5 (nm()) ["1"; "2"; "3"; "4"];
       S.of_list (nm()) ["one"; "42"; "five-hundred"], S.of_list (nm()) ["1"; "forty-two"; "500"],
         S.of_list (nm()) ["one"; "42"; "five-hundred"; "1"; "forty-two"; "500"];
       S.of_list ~min_depth:3 (nm()) ["1"; "forty-two"; "five-hundred"],
         S.of_list ~min_depth:3 (nm()) ["1"; "forty-two"; "500"],
         S.of_list ~min_depth:3 (nm()) ["five-hundred"; "1"; "forty-two"; "500"]] in
    let cardinal_tests = unary_tests "cardinal" S.cardinal
        [t0, 0; t1, 1; t2, 2; t1', 1; t2', 2; t3, 2; t3', 2; t4, 3; t4', 3] in
    let mem_tests = binary_tests "mem" S.mem
      [t0, e001, false; t0, e010, false;
       t1, e001, true; t1, e010, false;
       t2, e001, true; t2, e010, true; t2, e010', false; t2, e010'', false;
       t3, e001, true; t3, e010, true; t3, e010', false; t3, e010'', false;
       t4, e001, true; t4, e010, true; t4, e010', true; t4', e010'', false;
       t5', e010', true; t6', e010', true] in
    let equal_tests = binary_tests "equal" S.equal
        [t0, t0, true;
         t0, t1, false;
         t1, t1, true;
         t1, t1', false;
         t2, t2', false;
         t4', t4', true;
         t5', t4', false;
         t6', t5', false
        ] in
    let hash_eq_tests = binary_tests "hasheq" (fun x y -> let h = S.hash 42 in h x = h y)
      [t0, t0, true;
       t1, t1', false;
       t2, t2', false;
       t1', t2, false;
       t1', t2, false;
      ] in
    "Nominal Set" >::: (cardinal_tests@mem_tests@equal_tests@hash_eq_tests@union_tests)

  module M = Map.Make(Useful(AdaptonTypes.String))(Useful(AdaptonTypes.Int))(Key)(Grifola.Default.ArtLib)

  let nmap_suite = 
    let k0, k1, k2, k3, k4     = "a", "c", "d", "j", "gah"   in
    let v0, v1, v2, v3, v4, v5 =  1,   3,   4,   5,    6,  7 in
    let nt0 = M.empty ~min_depth:1 in
    let nt1, nt1' = M.nadd (nm()) nt0 k0 v0, M.nadd (nm()) nt0  k1 v1 in
    let nt2, nt2' = M.nadd (nm()) nt1 k1 v1, M.nadd (nm()) nt1' k0 v0 in
    let nt3, nt3' = M.nadd (nm()) nt2 k2 v2, M.nadd (nm()) nt2' k2 v2 in
    let nt4, nt4' = M.nadd (nm()) nt3 k3 v3, M.nadd (nm()) nt3' k3 v3 in
    let nt5, nt5' = M.nadd (nm()) nt4 k0 v5, M.nadd (nm()) nt4' k0 v5 in
    let ncardinal_tests = unary_tests "cardinal" M.cardinal
      [(*nt0, 0; nt1, 1; nt1', 1; nt2, 2; nt2', 2; nt3, 3; nt3', 3; nt4, 4; nt4', 4; nt5, 4*)] in
    let nmem_tests = binary_tests "mem" M.mem
      [nt0, k0, false; nt0, k1, false;
       M.nadd (Key.nondet ()) nt1 k0 v1, k0, true;
       nt1, k0, true; nt1', k0, false; nt1', k1, true;
       nt2, k1, true; nt2', k1, true; nt2', k0, true;
       nt3, k0, true; nt3', k0, true; nt3, k2, true;
       nt3', k2, true; nt3, k3, false; nt3', k3, false] in
    let nfind_tests = binary_tests "find" M.find
      [nt1, k0, Some v0; nt1', k1, Some v1;
       nt2, k0, Some v0; nt2', k1, Some v1;
       nt2, k1, Some v1; nt2', k0, Some v0;
       nt3, k0, Some v0; nt3', k1, Some v1;
       nt3, k1, Some v1; nt3', k0, Some v0;
       nt3, k2, Some v2; nt3', k2, Some v2;
       nt5, k0, Some v5; nt5', k1, Some v1;
       nt5, k1, Some v1; nt5', k0, Some v5;
       nt5, k2, Some v2; nt5', k2, Some v2;] in
    let nequal_tests = binary_tests "equal" M.equal
      [(M.force nt5), (M.force nt4), false] in
    print_endline (M.string (M.force nt5)) ;
    print_endline (M.string (M.force nt4)) ;
    "Nominal Map" >::: (ncardinal_tests@nmem_tests@nfind_tests@nequal_tests)

  let run () =
    run_test_tt_main bs_suite;
    run_test_tt_main nset_suite;
    run_test_tt_main nmap_suite;
    ()

end

let _ = Test.run ()
*)

include Adapton_lib

open Adapton_structures                 
open Adapton_core
open Primitives
open GrifolaType

module Types = AdaptonTypes
module Statistics = AdaptonStatistics
module ArtLib (* : ArtLibType *) = Grifola.Default.ArtLib
module Name : NameType = Key

module type Store = sig
    type sto
    type t = sto
    type a
    type b
    val mt : sto
    val lookup : sto -> a -> b option
    val ext : sto -> a -> b -> sto
    val hash : int -> sto -> int
    val string : sto -> string
    val sanitize : sto -> sto
    val equal : sto -> sto -> bool
  end
                      
module AssocStore (A:DatType)(B:DatType) = struct
  type a = A.t
  type b = B.t

  module St = SpreadTree.MakeSpreadTree(ArtLib)(Name)
                                       (Types.Tuple2(A)(B))
             
  type sto = St.List.Data.t
  type t = sto

  let mt = []
	     
  let lookup : sto -> 'a -> 'b option =
    failwith "todo"
             (*
    fun s x ->
    try Some (List.assoc x s) with Not_found -> None
              *)
						  
  let ext : sto -> 'a -> 'b -> sto =
    failwith "todo"
    (*
    fun s x v ->
    (x, v) :: s
     *)

  (* FIXME: degenerate hash *)
  let hash : int -> sto -> int =
    fun seed s ->
    0

  (* FIXME: *)
  let string : sto -> string = 
    fun s ->
    failwith "Not implemented"

  (* FIXME: no op *)
  let sanitize : sto -> sto = 
    fun s -> s

  let equal : sto -> sto -> bool = 
    fun s1 s2 -> s1 = s2

end

module StoStringInt = AssocStore (Types.String)(Types.Tuple2(Types.Int)(Types.Int))
open StoStringInt

type store = sto

type aexpr =
  | Int of int
  | Plus of aexpr * aexpr
  | Minus of aexpr * aexpr
  | Times of aexpr * aexpr
  | Var of string

type bexpr =
  | True
  | False
  | Not of bexpr
  | And of bexpr * bexpr
  | Or of bexpr * bexpr
  | Eq of aexpr * aexpr
  | Leq of aexpr * aexpr

type cmd =
  | Skip
  | Assign of string * aexpr
  | Seq of cmd * cmd
  | If of bexpr * cmd * cmd
  | While of bexpr * cmd

let rec aeval s = function
  | Int n -> n
  | Plus (e1, e2) -> (aeval s e1) + (aeval s e2)
  | Minus (e1, e2) -> (aeval s e1) - (aeval s e2)
  | Times (e1, e2) -> (aeval s e1) * (aeval s e2)
  | Var x -> 
     (match lookup s x with
      | Some (i, j) -> i
      | None -> failwith "Unset variable")
       
let rec beval s = function
  | True -> true
  | False -> false
  | Not b -> not (beval s b)
  | And (b1, b2) -> (beval s b1) && (beval s b2)
  | Or (b1, b2) -> (beval s b1) || (beval s b2)
  | Leq (a1, a2) -> (aeval s a1) <= (aeval s a2)
  | Eq (a1, a2) -> (aeval s a1) = (aeval s a2)


type 'a art_cmd =
  | Skip
  | Assign of string * aexpr
  | Seq of 'a art_cmd * 'a art_cmd
  | If of bexpr * 'a art_cmd * 'a art_cmd
  | While of bexpr * 'a art_cmd
  (* Boilerplate cases: *)
  | Art of 'a
  | Name of Name.t * 'a art_cmd
                        
module rec Cmd
           : sig
               module Data : DatType
               module Art : ArtType
             end
           with type Data.t = Cmd.Art.t art_cmd
            and type Art.Data.t = Cmd.Art.t art_cmd
            and type Art.Name.t = Name.t
                                  = struct
                       module Data = struct
                         type t = Cmd.Art.t art_cmd
                         let rec string x = failwith "todo"
                         let rec hash seed x = failwith "todo"
                         let rec equal xs ys = failwith "todo"
                         let rec sanitize x = failwith "todo"
                       end
                       (* Apply the library's functor: *)
                       module Art = ArtLib.MakeArt(Name)(Data)
                     end

module StoArt = ArtLib.MakeArt(Name)(StoStringInt)
                              
let rec ceval cmd s =
  (* next step is to use mk_mfn *)

  let mfn =
    StoArt.mk_mfn
      (Name.gensym "ceval")
      (module Types.Tuple2(StoStringInt)(Cmd.Data))
      (fun mfn (s, cmd) ->
       let ceval s c = mfn.mfn_data (s,c) in
       match cmd with
       | Skip -> s
       | Assign (x, a) -> 
	  let i = aeval s a in
	  (match lookup s x with
	   | None -> ext s x (i, 0)
	   | Some (_, count) ->
	      ext s x (i, count + 1))	 

       | Seq (c0, c1) -> ceval (ceval s c0) c1
       | If (b, c0, c1) ->
          (match beval s b with
             true -> ceval s c0
           | false -> ceval s c1)
       | (While (b, c)) as w -> ceval s (If (b, Seq(c, w), Skip))

       | Art a ->
          ceval s (Cmd.Art.force a)

       | Name(nm, cmd) ->
          StoArt.force (mfn.mfn_nart nm (s,cmd))
      )
  in
  mfn.mfn_data (cmd, s)




(*
let rec aevals s = function
  | Var x -> Int (lookup s x)
  | Plus (Int n, Int m) -> Int (n+m)
  | Plus (Int n, b) -> Plus(Int n, aevals s b)
  | Plus (a, b) -> Plus((aevals s a), b)

let rec bevals s = function
  | Leq (Int n, Int m) -> if n<=m then True else False
  | Leq (Int n, a) -> Leq (Int n, aevals s a)
  | Leq (a1, a2) -> Leq (aevals s a1, a2)
  | _ -> failwith "Oops!"

let rec cevals (s, c) = match c with
  | Assign (x, Int n) -> (ext s x n, Skip)
  | Assign (x, a) -> (s, Assign (x, aevals s a))
  | Seq (Skip, c2) -> (s, c2)
  | Seq (c1, c2) ->
     let s', c' = cevals (s, c1) in
     (s', Seq (c', c2))
  | If (True, c1, c2) -> (s, c1)
  | If (False, c1, c2) -> (s, c2)
  | If (b, c1, c2) ->
     (s, (If ((bevals s b), c1, c2)))
  | While (b, c) as w -> (s, If (b, Seq(c, w), Skip))
 *)

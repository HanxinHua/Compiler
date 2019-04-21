signature LIVENESS=
sig
	structure IGraph : GRAPH
	datatype igraph =
		IGRAPH of {graph: IGraph.graph,
				   tnode: Temp.temp -> IGraph.node,
				   gtemp: IGraph.node -> Temp.temp,
				   moves: (IGraph.node * IGraph.node) list}

	val interferenceGraph :
			Flow.flowgraph ->
				igraph * (Flow.Graph.node -> Temp.temp list)

	val show : TextIO.outstream * igraph -> unit
end

structure Liveness :> LIVENESS =
struct
	structure IGraph = Graph
	datatype igraph =
		IGRAPH of {graph: IGraph.graph,
				   tnode: Temp.temp -> IGraph.node,
				   gtemp: IGraph.node -> Temp.temp,
				   moves: (IGraph.node * IGraph.node) list}
	structure TempSet = RedBlackSetFn(type ord_key=Temp.temp val compare=Int.compare)
	structure NodeMap = RedBlackMapFn(type ord_key=Flow.Graph.node val compare=Flow.Graph.compare) (*node -> livein set * liveout set*)
	structure NtMap = RedBlackMapFn(type ord_key=IGraph.node val compare=IGraph.compare) (*node -> temp*)
	structure TnMap = RedBlackMapFn(type ord_key=Temp.temp val compare=Int.compare) (*temp -> node*)
	structure EdgeKey =
    struct
        type ord_key = {from: IGraph.node, to: IGraph.node}
        fun compare({from=s, to=d}, {from=s', to=d'}) =
            (case IGraph.compare(s,s') of
                EQUAL => IGraph.compare(d,d')
                | LESS => LESS
				| GREATER => GREATER)
    end

    structure EdgeSet = RedBlackSetFn(EdgeKey)

	fun getStart (node, mymap) = NodeMap.insert(mymap, node, (TempSet.empty, TempSet.empty))
	
	fun getLive (b, mymap, deft, uset, nodea::nodes) = let 

														val defs = case Flow.Graph.Table.look(deft, nodea) of NONE => []
																										| SOME tmps => tmps

														val uses = case Flow.Graph.Table.look(uset, nodea) of NONE => []
																										| SOME tmps => tmps

														val defset = TempSet.addList(TempSet.empty, defs)
														val useset = TempSet.addList(TempSet.empty, uses)
														val (livein', liveout') = valOf(NodeMap.find(mymap, nodea))
														val livein = TempSet.union(useset, TempSet.difference(liveout', defset))
														val succs = Flow.Graph.succ nodea
                            (* Union over all the liveIns of all successors. #1 since first elem is liveIn *)
														val liveout = foldl (fn (a,b) => TempSet.union(b, #1 (valOf(NodeMap.find(mymap, a))))) TempSet.empty succs

													in
														getLive(b andalso TempSet.equal(livein, livein') andalso TempSet.equal(liveout, liveout'),
																NodeMap.insert(mymap, nodea, (livein, liveout)), deft, uset, nodes)
													end
	  | getLive (b, mymap, deft, uset, nil) = (b, mymap)


	fun iteration (b, mymap, deft, uset, nodes) = let
													  val (b', map') = getLive (b, mymap, deft, uset, nodes)
												  in
													  if b' then map' else iteration (true, map', deft, uset, nodes)
												  end

	fun interferenceGraph (fg as Flow.FGRAPH{control = cfg,def = deft, use = uset, ismove = imt}) =
			let

				val nodes = Flow.Graph.nodes cfg
				
				val mymap = iteration(true, foldl getStart NodeMap.empty nodes, deft, uset, rev nodes)
				val ig = IGraph.newGraph()

				fun getMapping (nodea, (ntm, tnm)) =
					let
						val defs = getOpt (Flow.Graph.Table.look(deft, nodea), [])
						val uses = getOpt (Flow.Graph.Table.look(uset, nodea), [])

						fun addNode (a, (ntm', tnm')) = case TnMap.find(tnm', a) of NONE => (let val newn = IGraph.newNode ig
																			in (NtMap.insert(ntm', newn, a), TnMap.insert(tnm', a, newn))
																			end)
																| SOME b => (ntm', tnm')
					in
						foldl addNode (ntm, tnm) (defs@uses)
					end

				val (ntmap, tnmap) = foldl getMapping (NtMap.empty, TnMap.empty) nodes

				fun tnode tmp = case TnMap.find(tnmap, tmp) of NONE => (print("ERROR: No such temp found: "^MipsFrame.makestring tmp^"\n"); IGraph.errorNode ig)
														| SOME node => node

				fun gtemp (nde:IGraph.node) = case NtMap.find(ntmap, nde) of NONE => (print("ERROR: No such node found: "^IGraph.nodename nde^"\n"); ~1: Temp.temp)
														 | SOME tmp => tmp

				fun addEdge (node, eset) =
						let
							val LOs = case NodeMap.find(mymap, node) of SOME (lis, los) => TempSet.listItems(los)
																	| NONE => (print("ERROR: No such node found: "^IGraph.nodename node^"\n"); [])
							val defs = case Flow.Graph.Table.look(deft, node) of NONE => ([])
																		| SOME tmps => tmps
							fun addOneDef (tmp, ese) =
								let
									val mynode = tnode tmp
									fun addOneLO (lotmp, ese') =
										let
											val lonode = tnode lotmp
											val edge = {from = mynode, to = lonode}
											val edge' ={from = lonode, to = mynode}
										in
											if EdgeSet.member(ese', edge) orelse tmp=lotmp then ese'
											else (IGraph.mk_edge edge; EdgeSet.add(EdgeSet.add(ese', edge),edge'))
										end
								in
									foldl addOneLO ese LOs
								end
						in
							foldl addOneDef eset defs
						end

				val _ = foldl addEdge EdgeSet.empty nodes

				fun getMoves (node, l) = if isSome(Flow.Graph.Table.look(imt, node)) andalso valOf(Flow.Graph.Table.look(imt, node))
											then (let val deftemp = hd (valOf(Flow.Graph.Table.look(deft, node)))
													  val usetemp = hd (valOf(Flow.Graph.Table.look(uset, node)))
													in (tnode deftemp, tnode usetemp)::l
													end)

											else l
				val moves = foldl getMoves [] nodes

				fun getLO node = case NodeMap.find(mymap, node) of NONE => (print("ERROR: No such node found: "^IGraph.nodename node^"\n"); [])
																| SOME (li, lo) => TempSet.listItems lo
			in
				(IGRAPH{graph = ig,
					   tnode = tnode,
					   gtemp = gtemp,
					   moves = moves}, getLO)
			end


	fun show (outs, ig as IGRAPH{graph = g,
					   tnode = tnode,
					   gtemp = gtemp,
					   moves = moves}) =
			let
				val nodes = IGraph.nodes g

				fun emit (node, st) =
					let
						val adjs = IGraph.adj node
						fun findmove (nodei, nodej) ((n1, n2)::m)= if (IGraph.eq(nodei, n1) andalso IGraph.eq(nodej, n2)) orelse (IGraph.eq(nodei, n2) andalso IGraph.eq(nodej, n1))
																	then true
																	else findmove (nodei, nodej) m
						  | findmove (nodei, nodej) nil = false
						  
						fun emitadjs (a::m::l) = if findmove (a, node) moves then (IGraph.nodename a ^ "(" ^ MipsFrame.makestring (gtemp a) ^ ")")^ "(moveEdge), " ^ emitadjs(m::l) else (IGraph.nodename a ^ "(" ^ MipsFrame.makestring (gtemp a) ^ ")")^ ", " ^ emitadjs(m::l)
						  | emitadjs (a::m) = if findmove(a, node) moves then (IGraph.nodename a ^ "(" ^ MipsFrame.makestring (gtemp a) ^ ")")^ "(moveEdge)" else IGraph.nodename a ^ "(" ^ MipsFrame.makestring (gtemp a) ^ ")"
						  | emitadjs nil = ""
					in

						st^IGraph.nodename node^"("^MipsFrame.makestring (gtemp node)^")"^": "^ emitadjs adjs ^"\n"
					end
			in
                TextIO.output(outs,  foldl emit "" nodes)
			end

end

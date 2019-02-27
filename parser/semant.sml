structure A = Absyn

structure Semant :
  sig
    type expty = {exp: Translate.exp, ty: Types.ty}
    type venv = Env.enventry Symbol.table
    type tenv = Types.ty Symbol.table
    val transVar: (venv * tenv * A.var) -> expty
    val transExp: venv * tenv * A.exp -> expty
    val transDec: venv * tenv * A.dec -> {venv: venv, tenv: tenv}
    val transTy :        tenv * A.ty  -> Types.ty
  end =
struct

  type expty = {exp: Translate.exp, ty: Types.ty}
  type venv = Env.enventry Symbol.table
  type tenv = Types.ty Symbol.table
  type unique = unit ref
  val venv:venv = Env.base_venv
  val tenv:tenv = Env.base_tenv

  fun transProg() = () (*TODO*)

  fun checkSameType(ty1: Types.ty, ty2: Types.ty) = ty1 = ty1 orelse ty1 = Types.BOTTOM orelse ty2 = Types.BOTTOM
  fun checkLegacy(x: expty, y: expty) = checkSameType(#ty x, #ty y)


    fun  checkInt({exp=exp', ty=ty'}: expty, pos, print_) =
        if checkSameType(ty', Types.INT) then true
        else (if print_ then print("Error: Expected int token at " ^ Int.toString(pos)) else (); false)

    fun  checkStr({exp=exp', ty=ty'}: expty, pos, print_) =
        if  checkSameType(ty',Types.STRING) then true
        else (if print_ then print("Error: Expected string token at " ^ Int.toString(pos)) else (); false)

    fun actual_ty ty = case ty of Types.NAME(s,t) => actual_ty (valOf (!t))
  								 |  _              => ty

	fun searchTy(tenv,s,pos) = case Symbol.look(tenv, s) of SOME t => actual_ty t
													  | NONE   => (print(Int.toString(pos)^"Error: No such type defined  " ^ Symbol.name s);
																	Types.BOTTOM)
	fun getRecordParam tenv {name=name, escape=escape, typ=typ, pos=pos} = (name, searchTy(tenv,typ,pos))

  fun transExp(venv, tenv, root) =
  let
    datatype OpType = SORT | MATH | EQUALITY
    val equatable = []

    fun getTypeByOperation(A.NeqOp)    = EQUALITY
      | getTypeByOperation(A.EqOp)     = EQUALITY
      | getTypeByOperation(A.PlusOp)   = MATH
      | getTypeByOperation(A.MinusOp)  = MATH
      | getTypeByOperation(A.DivideOp) = MATH
      | getTypeByOperation(A.TimesOp)  = MATH
      | getTypeByOperation(A.GeOp)     = SORT
      | getTypeByOperation(A.GtOp)     = SORT
      | getTypeByOperation(A.LeOp)     = SORT
      | getTypeByOperation(A.LtOp)     = SORT

    and validateMath(left, right, pos) = if checkInt(trexp(left), pos, true) andalso checkInt(trexp(right), pos, true) then {exp=(), ty=Types.INT}
                                    else {exp=(), ty=Types.BOTTOM}
    and validateSort(left, right, pos) =
        let
            val l = trexp left
            val r = trexp right
        in
            if checkLegacy(l, r) andalso (checkInt(l, pos, false) orelse checkStr(l, pos, false)) then {exp=(), ty=Types.INT}
            else (print("Comparison Error: Malformed comparison at " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})
        end

    and validateEquality(left, right, pos) =
      let
        val l: expty = trexp left
        val r: expty = trexp right
      in
        case actual_ty(#ty l) of
            Types.INT => if checkInt(r, pos, true) then {exp=(), ty=Types.INT} else (print("Compared structures must be of same type: pos " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})
          | Types.STRING => if checkStr(r, pos, true) then {exp=(), ty=Types.INT} else (print("Compared structures must be of same type: pos " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})
          | Types.ARRAY(ty', unique') => if checkSameType(Types.ARRAY(ty', unique'), #ty r) then {exp=(), ty=Types.INT} else (print("Compared structures must be of same type: pos " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})
          | Types.RECORD(fields, unique') => if checkSameType(Types.RECORD(fields, unique'), #ty r) then {exp=(), ty=Types.INT} else (print("Compared structures must be of same type: pos " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})
          | _ => (print("Cannont campare structures at pos " ^ Int.toString(pos) ^ ": can only compare int, string, record, and array types"); {exp=(), ty=Types.BOTTOM})
      end

    and  trexp(A.IntExp i): expty = {exp=(), ty=Types.INT}
        |   trexp(A.StringExp (s,pos)) = {exp=(), ty=Types.STRING}
        |   trexp(A.NilExp) = {exp=(), ty=Types.UNIT}
        |   trexp(A.OpExp{left, oper, right, pos}) = (case getTypeByOperation oper of
                                                      MATH     => validateMath(left, right, pos)
                                                    | SORT     => validateSort(left, right, pos)
                                                    | EQUALITY => validateEquality(left, right, pos)
                                                )
        |   trexp(A.IfExp{test, then', else', pos}) =
                let
                    val expty' = trexp then'
                in
                    if checkInt(trexp test, pos, true) andalso checkLegacy(expty', trexp(getOpt(else', A.NilExp))) then {exp=(), ty=(#ty expty')}
                    else (print("Error: Invalid if conditional statement at pos " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})
                end
        |   trexp(A.WhileExp{test, body, pos}) =  if checkInt(trexp test, pos, true) andalso checkSameType(Types.UNIT, #ty (trexp body)) then {exp=(), ty=Types.UNIT}
                                                else (print("Error: While loop construction error at " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})
        |   trexp(A.ForExp{var, lo, hi, body, escape, pos}) = if checkInt(trexp lo, pos, true) andalso checkInt(trexp hi, pos, true) andalso checkSameType(Types.UNIT, #ty (trexp body)) then {exp=(), ty=Types.UNIT}
                                                    else (print("Error: For loop construction error at " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})
        |   trexp(A.BreakExp(_)) = {exp=(), ty=Types.BOTTOM}
        |   trexp(A.VarExp(v)) = {exp=(), ty=(trvar v)}
        |   trexp(A.AssignExp{var, exp, pos}) =
                let
                    val expTy = trexp exp
                    val varTy = trvar var
                in
                    if checkSameType(#ty expTy, varTy) then {exp=(), ty = #ty expTy}
                    else (print("Illegal assign expression at pos " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})
                end
        |   trexp(A.RecordExp{fields, typ, pos}) = (
                case Symbol.look(tenv, typ) of
                    SOME(t) => (case actual_ty(t) of
                        Types.RECORD(fieldTypes, unique') =>
                        let
                            fun getFieldTypes({exp, ty}) = () (*TODO*)
                            fun validateRecord() = ()
                        in
                            {exp=(), ty=Types.BOTTOM}(*TODO*)
                        end
                    |   _ => (print("Type mismatch in record usage at pos " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM}))
                |   NONE    => (print("Unknown type " ^ Symbol.name typ ^ " at pos " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})

            )
        |   trexp(A.SeqExp(exps)) =

                if List.null exps then {exp=(), ty=Types.UNIT} else {exp=(), ty=(#ty (trexp (#1 (List.last exps))))}

        |   trexp(A.LetExp{decs, body, pos}) =
                let
                    (* TODO val {venv', tenv'} = foldr (fn(declaration, {venv, tenv}) => {venv=venv1, tenv=tenv1} = transDec(venv, tenv, declaration)) {venv=venv, tenv=tenv} decs *)
                    val {exp=_, ty=bodyType} = transExp(venv, tenv, body)
                in
                    {exp=(), ty=bodyType}
                end
        |   trexp(A.ArrayExp{typ, size, init, pos}) = (
                case S.look(tenv, typ) of
                    SOME(at) => (
                        case actual_ty(at) of
                            Types.ARRAY(t, u) =>
                                if checkInt(trexp size, pos, true) andalso checkSameType(at, #ty (trexp init)) then {exp=(), ty=Types.ARRAY(t,u)}
                                else (print("Invalid array expression at pos " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})
                            | _ => (print("Type mismatch at array exp at pos " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})
                        )
                |   NONE => (print("Unknown type at pos " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})
            )
        |   trexp(A.CallExp{func, args, pos}) = (
                case S.look(venv, func) of
                    SOME(Env.FunEntry{formals, result}) =>
                    let
                        fun f(ty1, ty2, res) = res andalso checkSameType(ty1, ty2)
                    in
                        if (ListPair.foldr f true (formals, map (fn x => #ty (trexp x)) args)) then {exp=(), ty=result}
                        else (print("Type disagreement in function arguments at pos " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})
                        handle ListPair.UnequalLengths =>    (print("Argument error at pos " ^ Int.toString(pos) ^ ", expected " ^ Int.toString(length formals) ^ " function arguments, found " ^ Int.toString(length args));
                                                    {exp=(), ty=Types.BOTTOM})
                    end
                |   SOME(Env.VarEntry(_)) => (print("Expected a function idenifier, found a variable: pos " ^ Int.toString(pos));{exp=() ,ty=Types.BOTTOM})
                |   NONE => (print("Unknown symbol at pos " ^ Int.toString(pos)); {exp=(), ty=Types.BOTTOM})

            )
        and trvar (_) = Types.BOTTOM
    in
      trexp(root)
    end
  	and  transTy(tenv,ty) =
     case ty of A.NameTy(s, p) => Types.NAME(s, ref (SOME (searchTy(tenv,s,p))))
  			  | A.RecordTy(tl) => Types.RECORD(if tl=[] then [] else map (getRecordParam tenv) tl, ref (): Types.unique)
  		      | A.ArrayTy(s,p) => Types.ARRAY(searchTy(tenv,s,p), ref (): Types.unique )
    and transVar (venv, tenv, node) =
      let fun trvar (A.SimpleVar(id, pos)) =
  							(case Symbol.look(venv, id)
  							of SOME(Env.VarEntry{ty}) => {exp = (), ty = actual_ty ty}
                             | SOME(Env.FunEntry) => (print("Cannot h "))  
  							 | NONE => (print(Int.toString(pos)^"Error: undefined variable " ^ Symbol.name id);
  										{exp = (), ty = Types.BOTTOM}))
  			  | trvar (A.FieldVar(v, id, pos)) =
							let val {exp = (), ty = ty} = trvar(v)
							in
								(case ty of Types.RECORD(stl, u) => let fun searchField ((s,t)::m) id = if s = id then actual_ty t else searchField m id
																		  | searchField nil id  = (print(Int.toString(pos)^"Error: Field name is not defined in the record: " ^ Symbol.name (id));
																								   Types.BOTTOM)
																	in
																		{exp = (), ty = searchField stl id}
																	end
															 | _ => (print(Int.toString(pos)^"Error: Variable is not defined as a record: ");
																	{exp = (), ty = Types.BOTTOM})
															)
							end

  			  | trvar (A.SubscriptVar(v, exp, pos)) =  (*Do we have to check the bound?*)
							let val {exp = (), ty = ty} = trvar(v)
  							in
								(case ty of Types.ARRAY(t, u) =>  (if checkInt(transExp (venv,tenv,exp), pos, true)
																	then {exp = (), ty = actual_ty t}
																	else (print(Int.toString(pos)^"Error: the index is not int ");
																	{exp = (), ty = Types.BOTTOM}))
											| _               => (print(Int.toString(pos)^"Error: Variable is not defined as an array: ");
																 {exp = (), ty = Types.BOTTOM})
								)
  							end
		in
		trvar node
		end
    and transDec (venv, tenv, A.VarDec{name, escape, typ, init, pos}) =

    (let val {exp = exp, ty = ty} = transExp(venv, tenv, init)
		in
		case typ
			of SOME((s,p)) => if checkLegacy({exp=(), ty=searchTy (tenv,s,p)}, {exp=exp, ty=ty})
									then {venv=Symbol.enter(venv,name,Env.VarEntry{ty=ty}), tenv=tenv}
									else (print(Int.toString(pos)^"Error: Unmatched defined variable type " ^ Symbol.name name);
										  {venv=venv,tenv=tenv})
		     | NONE =>
				{venv=Symbol.enter(venv,name,Env.VarEntry{ty=ty}), tenv=tenv}

		end
		)

	  | transDec (venv, tenv, A.TypeDec[{name,ty,pos}]) =
			{venv=venv,
			 tenv=Symbol.enter(tenv,name,transTy(tenv,ty))}

	  | transDec (venv, tenv, A.FunctionDec[{name,params,body,pos,result}]) =
		let
			val SOME(result_ty) = case result of SOME(rt,pos) => Symbol.look(tenv,rt)
											   | NONE => SOME Types.UNIT
			fun transparam {name, escape, typ, pos} =
									case Symbol.look(tenv,typ)
										of SOME t => {name=name, ty=t}
									    | NONE => (print(Int.toString(pos)^"Error: Undefined parameter type " ^ Symbol.name name);
										  {name = name, ty = Types.BOTTOM})
			val params' = map transparam params
			val venv' = Symbol.enter(venv,name,Env.FunEntry{formals = map #ty params', result=result_ty})
			fun enterparam ({name=name, ty=ty}, venv) =
						Symbol.enter(venv,name,Env.VarEntry{ty=ty})
			val venv'' = foldl enterparam venv' params'
		in
			if checkLegacy(transExp(venv'',tenv, body), {exp=(), ty=result_ty})
							then {venv=venv',tenv=tenv}
							else  ( print(Int.toString(pos)^"Error: return type do not match " ^ Symbol.name name);
									{venv=venv',tenv=tenv})

		end
end

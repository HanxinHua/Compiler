structure Go =
struct
fun go file =
  let
    val _ = ErrorMsg.reset()
  in
    PrintAbsyn.print(TextIO.stdOut,Parse.parse file)
  end
end

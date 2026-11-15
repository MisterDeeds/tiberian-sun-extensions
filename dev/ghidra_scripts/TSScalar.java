// Finds instructions that use a scalar (e.g. a structure offset like 0xd60) and decompiles their functions.
// Arguments: <outdir> <tag> <maxDecomp> <scalar> [<scalar> ...]
//@category TiberianSun

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.util.*;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.scalar.Scalar;

public class TSScalar extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        File outDir = new File(args[0]);
        String tag = args[1];
        int maxDecomp = Integer.parseInt(args[2]);
        Set<Long> wanted = new HashSet<>();
        for (int i = 3; i < args.length; i++) wanted.add(Long.decode(args[i]));
        File decompDir = new File(outDir, "decomp");
        decompDir.mkdirs();
        Map<Function, String> funcs = new LinkedHashMap<>();
        try (PrintWriter pw = new PrintWriter(new FileWriter(new File(outDir, "scalar_" + tag + ".txt")))) {
            InstructionIterator it = currentProgram.getListing().getInstructions(true);
            while (it.hasNext() && !monitor.isCancelled()) {
                Instruction ins = it.next();
                for (int op = 0; op < ins.getNumOperands(); op++) {
                    for (Object o : ins.getOpObjects(op)) {
                        if (o instanceof Scalar && wanted.contains(((Scalar) o).getUnsignedValue())) {
                            Function f = getFunctionContaining(ins.getAddress());
                            pw.printf("%s  %-40s %s%n", ins.getAddress(), ins.toString(), f == null ? "?" : f.getName() + "@" + f.getEntryPoint());
                            if (f != null) funcs.putIfAbsent(f, ins.toString());
                        }
                    }
                }
            }
        }
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        int n = 0;
        for (Function f : funcs.keySet()) {
            if (n++ >= maxDecomp) break;
            DecompileResults r = decomp.decompileFunction(f, 120, monitor);
            try (PrintWriter pw = new PrintWriter(new FileWriter(new File(decompDir, tag + "_" + f.getEntryPoint() + ".c")))) {
                pw.printf("// %s @ %s%n", f.getName(), f.getEntryPoint());
                pw.println(r.decompileCompleted() ? r.getDecompiledFunction().getC() : "// failed");
            }
        }
        decomp.dispose();
    }
}

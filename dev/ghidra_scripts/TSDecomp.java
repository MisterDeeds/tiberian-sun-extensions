// Decompiles the functions that contain the given addresses.
// Arguments: <outdir> <tag> <address> [<address> ...]
//@category TiberianSun

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;

public class TSDecomp extends GhidraScript {

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        File decompDir = new File(args[0], "decomp");
        decompDir.mkdirs();
        String tag = args[1];

        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        for (int i = 2; i < args.length && !monitor.isCancelled(); i++) {
            Function f = getFunctionContaining(toAddr(args[i]));
            File out = new File(decompDir, tag + "_" + args[i] + ".c");
            try (PrintWriter pw = new PrintWriter(new FileWriter(out))) {
                if (f == null) {
                    pw.println("// No function at " + args[i]);
                    continue;
                }
                DecompileResults r = decomp.decompileFunction(f, 120, monitor);
                pw.printf("// %s @ %s  (%d bytes)%n", f.getName(), f.getEntryPoint(), f.getBody().getNumAddresses());
                pw.println(r.decompileCompleted() ? r.getDecompiledFunction().getC()
                    : "// Decompilation failed: " + r.getErrorMessage());
            }
        }
        decomp.dispose();
    }
}

// Lists every instruction that references an address inside [start, end) (globals and arrays), grouped by target.
// Arguments: <outdir> <tag> <start> <end>
//@category TiberianSun

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.util.*;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSet;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;

public class TSRangeRefs extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        Address start = toAddr(args[2]), end = toAddr(args[3]);
        TreeMap<Address, List<String>> byTarget = new TreeMap<>();
        ghidra.program.model.address.AddressIterator dests =
            currentProgram.getReferenceManager().getReferenceDestinationIterator(new AddressSet(start, end.subtract(1)), true);
        while (dests.hasNext()) {
            Address to = dests.next();
            for (Reference r : getReferencesTo(to)) {
                Instruction ins = getInstructionAt(r.getFromAddress());
                Function f = getFunctionContaining(r.getFromAddress());
                byTarget.computeIfAbsent(to, k -> new ArrayList<>()).add(String.format("%s %-34s %s", r.getFromAddress(),
                    ins == null ? "?" : ins.toString(), f == null ? "?" : f.getName()));
            }
        }
        try (PrintWriter pw = new PrintWriter(new FileWriter(new File(args[0], "range_" + args[1] + ".txt")))) {
            for (Map.Entry<Address, List<String>> e : byTarget.entrySet()) {
                pw.printf("%s (%d refs)%n", e.getKey(), e.getValue().size());
                int n = 0;
                for (String s : e.getValue()) { if (n++ < 6) pw.println("    " + s); }
            }
        }
    }
}

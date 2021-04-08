import click
import copy
import gzip


@click.command()
@click.option("--input-file", nargs=1, required=True, type=click.Path(exists=True))
@click.option("--output-file", nargs=1, required=True, type=click.Path(exists=False))
@click.option("--organism", nargs=1, required=True, type=click.STRING)
def run(input_file, output_file, organism):
    print_block = False
    all_found = list()
    cur_block = list()
    with gzip.open(input_file, "rt") as read_file:
        for line in read_file:
            if not line.startswith("#"):
                if line.strip() == "":
                    if print_block is True:
                        all_found.append(copy.deepcopy(cur_block))
                    cur_block = list()
                    print_block = False
                else:
                    if not line.startswith("a"):
                        _, s, _ = line.split(maxsplit=2)
                        org, _ = s.split(".", 1)
                        if org == organism:
                            print_block = True
                    cur_block.append(line)
    # Convert to bed.
    bed_recs = list()
    for x in all_found:
        for y in x:
            if y.split(" ", 2)[1].startswith(organism):
                if y.startswith("s"):
                    _, lhs, rhs = y.split(maxsplit=2)
                    tmp = lhs.split(".", 2)
                    cur_chrom = tmp[1]
                    start, length, _ = rhs.split(maxsplit=2)
                    start = int(start)
                    length = int(length)
                    end = start + length
                    bed_recs.append((cur_chrom, start, end))

    # Write sorted output:
    with open(output_file, "wt") as write_file:
        for x in sorted(bed_recs):
            write_file.write("{}\t{}\t{}\n".format(*x))

if __name__ == "__main__":
    run()


import click
import h5py
import pyBigWig
import pyfaidx


@click.command()
@click.option("--input-h5", nargs=1, required=True, type=click.Path(exists=True))
@click.option("--input-bed", nargs=1, required=True, type=click.Path(exists=True))
@click.option("--feature-file", nargs=1, required=True, type=click.Path(exists=True))
@click.option("--genome-file", nargs=1, required=True, type=click.Path(exists=True))
@click.option("--target-feature", nargs=1, required=True, type=click.STRING)
@click.option("--output-file", nargs=1, required=True, type=click.Path(exists=False))
def run(input_h5, input_bed, feature_file, genome_file, target_feature, output_file):
    feats = list()
    target_i = None
    with open(feature_file, "r") as read_file:
        i = 0
        for line in read_file:
            line = line.strip()
            if line and not line.startswith("#"):
                feats.append(line)
                if line == target_feature:
                    target_i = i
                i += 1
    if target_i is None:
        msg = "Could not find feature name of \"{}\"".format(target_feature)
        raise ValueError(msg)

    recs = list()
    with open(input_bed, "r") as read_file:
        for line in read_file:
            line = line.strip()
            if line and not line.startswith("#"):
                chrom, start, end = line.split("\t", 3)[:3]
                start = int(start)
                end = int(end)
                lhs = start + (4095 // 2)
                rhs = lhs + 1
                recs.append((chrom, lhs, rhs))

    # Create header.
    header = list()
    fa = pyfaidx.Fasta(genome_file)
    for k in fa.keys():
        header.append((k, len(fa[k])))

    # Write data.
    bw = pyBigWig.open(output_file, "w")
    bw.addHeader(header, maxZooms=0)
    h5 = h5py.File(input_h5, "r")
    for i in range(len(recs)):
        val = h5["data"][i, target_i]
        bw.addEntries([recs[i][0]], [recs[i][1]], ends=[recs[i][2]], values=[val])
    h5.close()
    bw.close()

if __name__ == "__main__":
    run()


import re

import pandas


# Load in metadata.
metadata = pandas.read_csv("interspecies_info.csv", sep=",")
accessions = sorted(set(metadata.accession.tolist()))
rna_accessions = ["SRX3353227", "SRX3353221"]

rule all:
    input:
        expand("data/{sample}.converted.sorted.cleaned.rg.reordered.dedup_peaks.narrowPeak", sample=accessions),
        expand("data/{sample}.converted.bam", sample=accessions),
        expand("data/{sample}.CPM.bw", sample=rna_accessions)


rule trim_pe:
    input:
        r1 = "data/{sample}_1.fastq.gz",
        r2 = "data/{sample}_2.fastq.gz"
    output:
        r1_trimmed = "data/{sample,[A-Z0-9]*}_1_val_1.fq.gz",
        r2_trimmed = "data/{sample,[A-Z0-9]*}_2_val_2.fq.gz",
        r1_report = "data/{sample,[A-Z0-9]*}_1.fastq.gz_trimming_report.txt",
        r2_report = "data/{sample,[A-Z0-9]*}_2.fastq.gz_trimming_report.txt"
    threads: 6
    shell:
        "trim_galore --paired {input.r1} {input.r2} -o data"


rule trim_se:
    input:
        "data/{sample}.fastq.gz"
    output:
        out = "data/{sample,[A-Z0-9]*}_trimmed.fq.gz",
        report = "data/{sample,[A-Z0-9]*}.fastq.gz_trimming_report.txt"
    threads: 6
    shell:
        "trim_galore {input} -o data"


rule align_pe:
    input:
        r1 = "data/{sample}_1_val_1.fq.gz",
        r2 = "data/{sample}_2_val_2.fq.gz",
        genome = "../data/oryLat2.normalized.fa"
    output:
        "data/{sample,[A-Z0-9]*}.bam"
    threads: 32
    shell:
        "bwa mem -t 24 {input.genome} {input.r1} {input.r2} | "
        "samtools sort -o {output}"


rule align_se:
    input:
        reads = "data/{sample}_trimmed.fq.gz",
        genome = "../data/oryLat2.normalized.fa"
    output:
        "data/{sample,[A-Z0-9]*}.bam"
    threads: 32
    shell:
        "bwa mem -t 24 {input.genome} {input.reads} | "
        "samtools sort -o {output}"


rule align_pe_rna_danRer:
    input:
        r1 = "data/{sample}_1_val_1.fq.gz",
        r2 = "data/{sample}_2_val_2.fq.gz"
    output:
        "data/{sample,SRX3353221}.sorted.bam"
    params:
        genome = "../data/danRer10"
    threads: 32
    shell:
        "hisat2 -p 24 -x {params.genome} -1 {input.r1} -2 {input.r2} | "
        "samtools view -h -bF 4 | "
        "samtools sort --reference {params.genome}.fa -o {output}"


rule align_se_rna_oryLat:
    input:
        reads = "data/{sample}_trimmed.fq.gz"
    output:
        "data/{sample,SRX3353227}.sorted.bam"
    params:
        genome = "../data/oryLat2"
    threads: 32
    shell:
        "hisat2 -p 24 -x {params.genome} -U {input.reads} | "
        "samtools view -h -bF 4 | "
        "samtools sort --reference {params.genome}.fa -o {output}"


rule samtools_index_rna_bam:
    input:
        "data/{sample}.sorted.bam"
    output:
        "data/{sample,[A-Z0-9]*}.sorted.bai"
    shell:
        "samtools index {input} {output}"


rule rna_normalized_coverage:
    input:
        bam="data/{sample}.sorted.bam",
        bai="data/{sample}.sorted.bai"
    output:
        "data/{sample,[A-Z0-9]*}.CPM.bw"
    shell:
        "bamCoverage --binSize 1 --normalizeUsing CPM --bam {input.bam} --outFileName {output} --outFileFormat bigwig"


rule convert_bam:
    input:
        "data/{sample}.bam"
    output:
        "data/{sample,[A-Z0-9]*}.converted.bam"
    shell:
        "samtools view -h -bF 4 -q 1 {input} >{output}"

rule picard_sort:
    input:
        "data/{sample}.converted.bam"
    output:
        "data/{sample,[A-Z0-9]*}.converted.sorted.bam"
    shell:
        "picard SortSam I={input} O={output} SORT_ORDER=coordinate"


rule picard_index:
    input:
        "data/{sample}.converted.sorted.bam"
    output:
        "data/{sample,[A-Z0-9]*}.converted.sorted.bai"
    shell:
        "picard BuildBamIndex I={input}"


rule clean_bam:
    input:
        "data/{sample}.converted.sorted.bam"
    output:
        "data/{sample,[A-Z0-9]*}.converted.sorted.cleaned.bam"
    shell:
        "picard CleanSam I={input} O={output}"


rule mod_rg_bam:
    input:
        "data/{sample}.converted.sorted.cleaned.bam"
    output:
        "data/{sample,[A-Z0-9]*}.converted.sorted.cleaned.rg.bam"
    params:
        sm = "{sample}"
    shell:
        "picard AddOrReplaceReadGroups I={input} O={output} LB={params.sm} PU={params.sm} SM={params.sm} PL=ILLUMINA"


rule reorder_bam:
    input:
        bam="data/{sample}.converted.sorted.cleaned.rg.bam",
        genome="../data/oryLat2.normalized.fa"
    output:
        "data/{sample,[A-Z0-9]*}.converted.sorted.cleaned.rg.reordered.bam"
    shell:
        "picard ReorderSam I={input.bam} O={output} R={input.genome} CREATE_INDEX=TRUE"


rule mark_duplicates:
    input:
        "data/{sample}.converted.sorted.cleaned.rg.reordered.bam"
    output:
        bam="data/{sample,[A-Z0-9]*}.converted.sorted.cleaned.rg.reordered.dedup.bam",
        metrics="data/{sample,[A-Z0-9]*}.converted.sorted.cleaned.rg.reordered.dedup.dedup_metrics.txt"
    shell:
        "picard MarkDuplicates REMOVE_DUPLICATES=true I={input} O={output.bam} M={output.metrics}"


rule index_dedup:
    input:
        "data/{sample}.converted.sorted.cleaned.rg.reordered.dedup.bam"
    output:
        "data/{sample,[A-Z0-9]*}.converted.sorted.cleaned.rg.reordered.dedup.bai"
    shell:
        "gatk BuildBamIndex --INPUT {input}"


rule call_peaks:
    input:
        bam="data/{sample}.converted.sorted.cleaned.rg.reordered.dedup.bam",
        bai="data/{sample}.converted.sorted.cleaned.rg.reordered.dedup.bai"
    output:
        "data/{sample,[A-Z0-9]*}.converted.sorted.cleaned.rg.reordered.dedup_peaks.narrowPeak"
    shell:
        "echo macs2 callpeak --nomodel -g 8.1e8 -f BAM -q 1e-05 -t {input.bam} --outdir ./data --name $(basename {output} _peaks.narrowPeak)"


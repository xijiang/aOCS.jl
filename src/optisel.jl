"""
    function initR(dir, noff)
Initialize R environment for optiSel. These codes only need to be run once.
Call this once before calling `optisel()`.
"""
function initR(dir, noff)
    ppd = "$dir/ydh"     # phased genotypes for ydh directory
    rbd = "$dir/refs"    # reference breeds directory
    mtd = "$dir/match"   # match directory
    otd = "$dir/other"   # other information directory
    Ne, L = 100, 1
    @rput dir ppd rbd mtd otd Ne L noff
    
    R"""
        # to be run once
        library(optiSel)
        library(data.table)
        # below are IDs in my codes, changes every generation
        animals <- optiSel::read.indiv(file.path(ppd, '0.Chr1.phased'), skip=0, cskip=2)
        lmp <- data.table::fread(paste0(otd, '/map.txt'))
        rfiles <- paste0(rbd, '/Others.Chr', 1:18, '.phased')
        cont <- data.frame(age=1, male=0.5, female=0.5)
        # phen for the base generation, later generations will be generated by my function
        phen <- fread(paste0(otd, "/sex"))
        phen <- cbind(phen, Sire = NA, Dam = NA, Born = 0, Breed="Y_YDH", EBV = NA)
        phen <- phen[, c(1, 3, 4, 5, 2, 6, 7)]
    """
end

function initpt(grt, nid)
    ids = String[]
    for i in 1:nid
        push!(ids, "$grt-$i")
    end
    sex = rand(["male", "female"], nid)
    @rput ids sex
    R"""
      phen <- data.table(Indiv = ids, Sire = NA, Dam = NA, Born = grt + 1, Sex = sex, Breed="Y_YDH", EBV = NA)
    """
end

"""
    function optipm(grt)
Find the optimum mating pairs of the current generation (`grt`) with `optiSel`.
"""
function optipm(grt; minSNP=20, minL=2.5)
    @rput grt minSNP minL
    R"""
        bfiles <- paste0(ppd, '/', grt, '.Chr', 1:18, '.phased')
        fSEG <- segIBD(bfiles, lmp, minSNP = minSNP, minL = minL, keep = animals, skip=0, cskip = 2)
        Pig <- fread(paste0(otd, '/genotyped.id'))
        mfiles <- paste0(mtd, '/', grt, '.Chr', 1:18, '.txt')
        Comp <- segBreedComp(mfiles, lmp)
        setnames(Comp, old='native', new='segNC')
        fSEGN <- segIBDatN(list(hap.thisBreed=bfiles, hap.refBreed=rfiles, match=mfiles), Pig, lmp, thisBreed='Y_YDH', minSNP=20, minL=2.5, ubFreq=0.01)
        phen <- merge(phen, Comp[, c("Indiv", "segNC")], on="Indiv")
        phen <- merge(phen, data.frame(Indiv=names(diag(fSEG)), F=(2*fSEG[row(fSEG)==col(fSEG)]-1)), on="Indiv")
        cand <- candes(phen = phen, fSEG = fSEG, fSEGN = fSEGN, cont = cont)
        ub.fSEG <- cand$mean$fSEG + (1 - cand$mean$fSEG) / (2 * Ne * L)
        ub.fSEGN <- cand$mean$fSEGN + (1 - cand$mean$fSEGN) / (2 * Ne * L)
        females <- cand$phen$Sex == 'female' & cand$phen$isCandidate
        ub <- setNames(rep(0.00625, sum(females)), cand$phen$Indiv[females])
        con <- list (ub = ub, ub.fSEG = ub.fSEG, ub.fSEGN = ub.fSEGN)
        fit <- opticont('max.segNC', cand, con, solver='cccp', quiet=TRUE)
        Candidate <- fit$parent
        Candidate$n <- noffspring(Candidate, noff, random=TRUE)$nOff
        Mating <- matings(Candidate, Kin=fSEG)
    """
    @rget Mating
    return Mating
end

function pkped(mating, id)
    ln = 1 # line number
    sln = Set{Int}() # selected line number
    dms = Dict{String, Int}() # dams to be used
    mating.n = Int.(mating.n)
    for (_, ma, nsib) in eachrow(mating)
        if haskey(dms, ma)
            dms[ma] > nsib && continue
            sln = setdiff(sln, [ln])
            push!(sln, ln)
        end
        dms[ma] = nsib
        push!(sln, ln)
        ln += 1
    end
    idc = Dict{String, Int}()
    for (i, x) in enumerate(id)
        idc[x] = i
    end
    pm = zeros(Int, sum(mating[sort(collect(sln)), :n]), 2)
    ln = 1
    for i in sln
        pa, ma, nsib = mating[i, :]
        
        for _ in 1:Int(nsib)
            pm[ln, 1] = idc[pa]
            pm[ln, 2] = idc[ma]
            ln += 1
        end
    end
    pm
end

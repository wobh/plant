#!/bin/zsh

#http://downloads.sourceforge.net/project/ecls/ecls/13.5/ecl-13.5.1.tgz

if [[ -d ".plant" ]]
then
    PROJECT=`basename $PWD`
    COMMAND=$1
    OPTIONS=($@[2,${#}])
else
    COMMAND=$1
    PROJECT=$2
    if [[ -d $PROJECT ]]
    then
        cd $PROJECT
    else
        if [[ -z "$PROJECT" ]]; then
            PROJECT=`basename $PWD`
        fi
    fi
    OPTIONS=($@[3,${#}])
fi

if [[ -f ".plant/plantrc" && -z "$PLANT_LISP" ]]; then
    source .plant/plantrc
else
    if [[ -z "$PLANT_LISP" ]]; then
        PLANT_LISP=sbcl
    fi

    case $PLANT_LISP in
        sbcl)
            NOUSERINIT=--no-userinit
            LOAD=--load
            EVAL=--eval
            SLAD='(save-lisp-and-die #P".plant/'$PLANT_LISP-$PROJECT'" :executable t :purify t)'
            ;;
        ccl*)
            NOUSERINIT=-n
            LOAD=-l
            EVAL=-e
            SLAD='(save-application #P".plant/'$PLANT_LISP-$PROJECT'" :prepend-kernel t :purify t)'
            ;;
        *)
            echo "$PLANT_LISP is not currently supported by plant."
            exit 2
            ;;
    esac
fi

mkPlantRC() {
    if [[ -f .plant/plantrc ]]; then
        rm .plant/plantrc
    fi

    touch .plant/plantrc
    echo PLANT_LISP=$PLANT_LISP >> .plant/plantrc
    echo NOUSERINIT=$NOUSERINIT >> .plant/plantrc
    echo LOAD=$LOAD >> .plant/plantrc
    echo EVAL=$EVAL >> .plant/plantrc
    echo SLAD="'"$SLAD"'" >> .plant/plantrc
}

runLisp() {
    .plant/$PLANT_LISP-$PROJECT $NOUSERINIT $@
}

mkLocalSymlink() {
    TARGET=../../${1%%.git}
    pushd .quicklisp/local-projects
    ln -s $TARGET
    popd
}

buildLisp() {
    if [[ ! -d .plant ]]; then
        mkdir .plant
    fi 
    
    $PLANT_LISP $NOUSERINIT $LOAD .quicklisp/setup.lisp \
        $LOAD ~/.plant/setup.lisp \
        $EVAL '(ql:quickload '"'"'(:swank :alexandria '$1'))' \
        $EVAL $SLAD
    mkPlantRC
}

installQuicklisp() {
    if [[ -f .quicklisp/setup.lisp ]]; then
        return 0
    fi
    
    wget http://beta.quicklisp.org/quicklisp.lisp

    $PLANT_LISP $NOUSERINIT $LOAD quicklisp.lisp \
        $EVAL '(quicklisp-quickstart:install :path #P".quicklisp/")' \
        $EVAL '(quit)'

    rm quicklisp.lisp
}

newProject() {
    $PLANT_LISP $NOUSERINIT $LOAD .quicklisp/setup.lisp \
        $LOAD ~/.plant/setup.lisp \
        $EVAL '(ql:quickload :quickproject)' \
        $EVAL '(quickproject:make-project #P"'$PWD/$PROJECT/src/'" :name "'$PROJECT'")' \
        $EVAL '(quit)'

    mkLocalSymlink $PROJECT
}

new() {
    if [[ -d .plant ]]; then
        echo "ERROR: Creating a project under another project is not supported."
        exit 1
    fi
    
    if [[ -e $PROJECT ]]; then
        echo "ERROR: $PROJECT already exists."
        exit 1
    fi

    mkdir $PROJECT
    cd $PROJECT

    installQuicklisp
    
    buildLisp

    newProject
}

init() {
    if [[ -d .plant ]]; then
        echo "This is already a working plant project!"
        return 0
    fi

    installQuicklisp
    buildLisp
}

rebuild() {
    # this is it's own function at the moment because at some point
    # we want to track the quickloads that were setup so we can also
    # add those during the rebuild step
    buildLisp
}

quickloads() {
    if [[ -f .plant/$PLANT_LISP-$PROJECT ]]; then
        if [[ -e ".quicklisp" ]]; then
            buildLisp "$OPTIONS"
        else
            echo "ERROR: $PROJECT does not appear to be a valid project."
            exit 1
        fi
    else
        echo "ERROR: Unable to find .plant/$PLANT_LISP-$PROJECT. Perhaps $PROJECT isn't a valid plant project."
        exit 1
    fi
}

run() {
    runLisp $OPTIONS
}

swank() {
    runLisp $OPTIONS $EVAL "(swank:create-server :dont-close t)"
}

includeLocalProject() {
    TYPE=$OPTIONS[1]
    URL=$OPTIONS[2]

    echo $TYPE, $URL

    case $TYPE in
        git|hg)
            $TYPE clone $URL
            ;;
        wget)
            $TYPE $URL
            ;;
        *)
            echo "ERROR: This method of local project retrieval is currently unsupported."
            exit 1
            ;;
    esac

    mkLocalSymlink `basename $URL`
}

help() {
    echo "plant new <project name>"
    echo 'plant quickloads :system :system :system ...'
    echo 'plant swank [params]'
    echo 'plant run [params]'
    echo 'plant rebuild'
    echo 'plant include [git|hg|wget] <url>'
}

# "main"
case $COMMAND in
    help)
        help
        ;;
    new)
        new
        ;;
    init)
        init
        ;;
    quickloads)
        quickloads
        ;;
    swank)
        swank
        ;;
    run)
        run
        ;;
    rebuild)
        rebuild
        ;;
    include)
        includeLocalProject
        ;;
    *)
        help
        exit 1
        ;;
esac
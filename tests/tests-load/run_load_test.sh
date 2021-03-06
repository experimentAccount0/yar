#!/usr/bin/env bash
#
# after docker images have been built, this script spins up a yar
# deployment and runs a load test against that deployment
#

#
# given an input file (geneated by apache benchmark), generate
# an output file which represents the nth percentile of the
# input file based on the 5th column (request time) in the
# input file.
#
# exit codes
#   0   always
#
take_percentile_and_rebase_time() {
    local PERCENTILE=${1:-}
    local INPUT_FILENAME=${2:-}
    local OUTPUT_FILENAME=${3:-}

    local FIRST_EPOCH_TIME=$(tail -n +2 $INPUT_FILENAME | awk 'BEGIN {min = 9999999999; FS = "\t"} ; { if($2 < min) {min = $2} } END { print min }')

    NUM_LINES_IN_FILE=$(tail -n +2 $INPUT_FILENAME | wc -l)
    NUM_LINES_IN_PERCENTILE=$(python -c "print int($NUM_LINES_IN_FILE * float($PERCENTILE)/100)")

    sort \
        --field-separator=$'\t' \
        --key=5 \
        -n \
        $INPUT_FILENAME | \
    head \
        -n $NUM_LINES_IN_PERCENTILE | \
    awk \
        -v first_epoch_time="$FIRST_EPOCH_TIME" \
        'BEGIN {FS = "\t"; OFS = "\t"} ; \
        {print $1, $2 - first_epoch_time, $3, $4, $5, $6; }' | \
    sort \
        --field-separator=$'\t' \
        --key=2 \
        -n \
        > $OUTPUT_FILENAME

    return 0
}

#
# given an input file (geneated by one of the yar servers), generate
# an output file which represents the nth percentile of the input file
# based on the 2nd column (request time) in the input file.
#
# the input file is assumed to have no header rows
#
# exit codes
#   0   always
#
generate_yar_server_log_file_percentile() {
    local PERCENTILE=${1:-}
    local INPUT_FILENAME=${2:-}
    local OUTPUT_FILENAME=${3:-}

    NUM_LINES_IN_FILE=$(cat $INPUT_FILENAME | wc -l)
    NUM_LINES_IN_PERCENTILE=$(python -c "print int($NUM_LINES_IN_FILE * float($PERCENTILE)/100)")

    sort \
        --field-separator=$'\t' \
        --key=2 \
        -n \
        $INPUT_FILENAME | \
    head \
        -n $NUM_LINES_IN_PERCENTILE | \
    sort \
        --field-separator=$'\t' \
        --key=1 \
        -n \
        > $OUTPUT_FILENAME

    return 0
}

#
# this function encapsulates the real meat of the load test
#
# exit codes
#   0   ok
#
run_load_test() {
    local TEST_PROFILE=${1:-}
    local CONCURRENCY=${2:-}
    local RESULTS_DIR=${3:-}

    local NUMBER_OF_REQUESTS=`get_from_json '\["number_of_requests"\]' 5000 < $TEST_PROFILE`
    local PERCENTILE=`get_from_json '\["percentile"\]' 98 < $TEST_PROFILE`
    local PERCENT_BASIC_CREDS=`get_from_json '\["percent_basic_creds"\]' 90 < $TEST_PROFILE`

    local ZPCONCURRENCY=$(left_zero_pad $CONCURRENCY 4)

    local RESULTS_FILE_BASE_NAME=$RESULTS_DIR/$ZPCONCURRENCY-$NUMBER_OF_REQUESTS

    #
    # test is about to begin ... time to start collecting metrics
    #
    local DOCKER_CONTAINER_DATA=$RESULTS_DIR/$ZPCONCURRENCY-$NUMBER_OF_REQUESTS
    mkdir -p $DOCKER_CONTAINER_DATA

    echo "$CONCURRENCY: Spinning up a deployment"
    if ! $SCRIPT_DIR_NAME/../spin_up_deployment.sh -s -d $DOCKER_CONTAINER_DATA -p $TEST_PROFILE; then
        echo "$CONCURRENCY: Error spinning up deployment"
        return 1
    fi
    local AUTH_SERVICE_LB=$(get_deployment_config "AUTH_SERVICE_LB_END_POINT" "")
    echo "$CONCURRENCY: Deployment end point = $AUTH_SERVICE_LB"

    #
    # test is about to begin ... time to start collecting metrics
    #
    start_collecting_metrics

    #
    # all the setup is now complete ... load generation is next ...
    #
    local RESULTS_DATA=$RESULTS_FILE_BASE_NAME/raw-data.tsv
    if [ -r ~/.yar.creds.random.set ]; then

        echo "$CONCURRENCY: Using locust"

        echo "$CONCURRENCY: Starting to drive load"

        local LOCUST_LOGFILE=$RESULTS_FILE_BASE_NAME/locust-logfile.tsv
        local LOCUST_STDOUT_AND_STDERR=$RESULTS_FILE_BASE_NAME/locust-stdout-and-stderr.tsv

        locust \
            -f "$SCRIPT_DIR_NAME/locustfile.py" \
            -H http://$AUTH_SERVICE_LB \
            --no-web \
            -n $NUMBER_OF_REQUESTS \
            -c $CONCURRENCY \
            -r $CONCURRENCY \
            --logfile=$LOCUST_LOGFILE \
            >& $LOCUST_STDOUT_AND_STDERR
        if [ $? != 0 ]; then
            echo "$CONCURRENCY: Warning - error detected while driving load"
        fi

        grep TO_GET_TAB_TO_WORK $LOCUST_LOGFILE > $RESULTS_DATA

        rm -f $TEMP_RESULTS_DATA >& /dev/null

    else

        echo "$CONCURRENCY: Using Apache Bench"

        echo "$CONCURRENCY: Getting creds"
        local API_KEY=$(get_creds_config "API_KEY")
        # :TODO: what if API_KEY doesn't exist?

        echo "$CONCURRENCY: Starting to drive load"

        ab \
            -c $CONCURRENCY \
            -n $NUMBER_OF_REQUESTS \
            -A $API_KEY: \
            -g $RESULTS_DATA \
            http://$AUTH_SERVICE_LB/dave.html \
            >& /dev/null

    fi

    #
    # test is over ... we can stop collecting metrics
    #
    stop_collecting_metrics

    #
    # all that's left to do now is generate some graphs for inclusion
    # in the summary report
    #
    echo "$CONCURRENCY: Generating graphs"

    #
    # generate a section title page for summary report
    #
    REPORT_TEXT="Concurrency = $CONCURRENCY"
    REPORT_TEXT="$REPORT_TEXT\n\n$(remove_comments_and_format_json < $TEST_PROFILE)"
    convert \
        -background lightgray \
        -fill black \
        -size 3200x1800 \
        label:"$REPORT_TEXT" \
        -gravity center \
        $RESULTS_FILE_BASE_NAME-00-section-title.png

    #
    # if locust is the load driver it will output metrics every 2 seconds
    # that can be parsed so we can graph the requests/second and # of errors
    #
    if [ "$LOCUST_STDOUT_AND_STDERR" != "" ]; then

        local GRAPH_TITLE="Requests / Second and Errors - $START_TIME"
        local GRAPH_TITLE="$GRAPH_TITLE: Concurrency = $CONCURRENCY"

        gen_rps_and_errors_graph \
            "$GRAPH_TITLE" \
            "$LOCUST_STDOUT_AND_STDERR" \
            "$RESULTS_FILE_BASE_NAME-01-rps_and_errors.png"

    fi

    #
    # take load driver's tsv output file and use gnuplot to create a
    # histogram of all response times
    #
    local RESULTS_DATA_PERCENTILE=$(mktemp)

    take_percentile_and_rebase_time \
        $PERCENTILE \
        $RESULTS_DATA \
        $RESULTS_DATA_PERCENTILE

    TITLE="yar Response Time - $START_TIME"
    TITLE="$TITLE: Concurrency = $CONCURRENCY"
    TITLE="$TITLE; ${PERCENTILE}th Percentile"
    gnuplot \
        -e "input_filename='$RESULTS_DATA_PERCENTILE'" \
        -e "output_filename='$RESULTS_FILE_BASE_NAME-02-yar-response-time.png'" \
        -e "title='$TITLE'" \
        $SCRIPT_DIR_NAME/gp.cfg/response_time

    TITLE="yar Response Time - $START_TIME"
    TITLE="$TITLE: Concurrency = $CONCURRENCY"
    TITLE="$TITLE; ${PERCENTILE}th Percentile"
    gnuplot \
        -e "input_filename='$RESULTS_DATA_PERCENTILE'" \
        -e "output_filename='$RESULTS_FILE_BASE_NAME-03-yar-response-time-by-time-in-test.png'" \
        -e "title='$TITLE'" \
        $SCRIPT_DIR_NAME/gp.cfg/response_time_by_time

    #
    # during the load test, the auth services were making requests
    # to the key service LB. the statements below extract timing
    # information about the requests from the auth service's
    # log and then plots 2 different graphs of response times.
    #
    TEMPFILE=$(mktemp)
    cat $DOCKER_CONTAINER_DATA/Auth-Service-*/auth_service_log | \
        grep "Key Service.*responded in [0-9]\+ ms$" | \
        awk 'BEGIN {FS = "\t"; OFS = "\t"}; { print int($1 / 1000), $5 }' | \
        sed -s "s/\tKey Service.*responded in /\t/g" |
        sed -s "s/[[:space:]]ms$//g" \
        > $TEMPFILE

    PERCENTILETEMPFILE=$(mktemp)
    generate_yar_server_log_file_percentile \
        $PERCENTILE \
        $TEMPFILE \
        $PERCENTILETEMPFILE

    TITLE="Key Service Response Time - $START_TIME"
    TITLE="$TITLE: Concurrency = $CONCURRENCY"
    TITLE="$TITLE; ${PERCENTILE}th Percentile"
    gnuplot \
        -e "input_filename='$PERCENTILETEMPFILE'" \
        -e "output_filename='$RESULTS_FILE_BASE_NAME-04-key-service-response-time.png'" \
        -e "title='$TITLE'" \
        $SCRIPT_DIR_NAME/gp.cfg/yar_server_response_time

    TITLE="Key Service Response Time - $START_TIME"
    TITLE="$TITLE: Concurrency = $CONCURRENCY"
    TITLE="$TITLE; ${PERCENTILE}th Percentile"
    gnuplot \
        -e "input_filename='$PERCENTILETEMPFILE'" \
        -e "output_filename='$RESULTS_FILE_BASE_NAME-05-key-service-response-time-by-time-in-test.png'" \
        -e "title='$TITLE'" \
        $SCRIPT_DIR_NAME/gp.cfg/yar_server_response_time_by_time

    rm -f $PERCENTILETEMPFILE >& /dev/null
    rm -f $TEMPFILE >& /dev/null

    #
    # during the load test the key service was making requests
    # to the key store. the statements below extract timing
    # information about the requests from the key service's
    # log and then plots 2 different graphs of response times.
    #
    TEMPFILE=$(mktemp)
    cat $DOCKER_CONTAINER_DATA/Key-Service*/key_service_log | \
        grep "Key Store.*responded in [0-9]\+ ms$" | \
        awk 'BEGIN {FS = "\t"; OFS = "\t"}; { print int($1 / 1000), $5 }' | \
        sed -s "s/\tKey Store.*responded in /\t/g" |
        sed -s "s/[[:space:]]ms$//g" \
        > $TEMPFILE

    PERCENTILETEMPFILE=$(mktemp)
    generate_yar_server_log_file_percentile \
        $PERCENTILE \
        $TEMPFILE \
        $PERCENTILETEMPFILE

    TITLE="Key Store Response Time - $START_TIME"
    TITLE="$TITLE: Concurrency = $CONCURRENCY"
    TITLE="$TITLE; ${PERCENTILE}th Percentile"
    gnuplot \
        -e "input_filename='$PERCENTILETEMPFILE'" \
        -e "output_filename='$RESULTS_FILE_BASE_NAME-06-key-store-response-time.png'" \
        -e "title='$TITLE'" \
        $SCRIPT_DIR_NAME/gp.cfg/yar_server_response_time

    TITLE="Key Store Response Time - $START_TIME"
    TITLE="$TITLE: Concurrency = $CONCURRENCY"
    TITLE="$TITLE; ${PERCENTILE}th Percentile"
    gnuplot \
        -e "input_filename='$PERCENTILETEMPFILE'" \
        -e "output_filename='$RESULTS_FILE_BASE_NAME-07-key-store-response-time-by-time-in-test.png'" \
        -e "title='$TITLE'" \
        $SCRIPT_DIR_NAME/gp.cfg/yar_server_response_time_by_time

    rm -f $PERCENTILETEMPFILE >& /dev/null
    rm -f $TEMPFILE >& /dev/null

    #
    # during the load test the auth service was making requests
    # to the nonce store. the statements below extract timing
    # information about the requests from the auth service's
    # log and then plots graphs of response times.
    #

    TEMPFILE=$(mktemp)
    cat $DOCKER_CONTAINER_DATA/Auth-Service-*/auth_service_log | \
        grep "Nonce Store.*responded in [0-9]\+ us$" | \
        awk 'BEGIN {FS = "\t"; OFS = "\t"}; {print int($1 / 1000), $5}' | \
        sed -s "s/\tNonce Store.*responded in/\t/g" |
        sed -s "s/[[:space:]]us$//g" | \
        awk 'BEGIN {FS = "\t"; OFS = "\t"}; {print $1, int($2 / 1000)}' \
        > $TEMPFILE

    PERCENTILETEMPFILE=$(mktemp)
    generate_yar_server_log_file_percentile \
        $PERCENTILE \
        $TEMPFILE \
        $PERCENTILETEMPFILE

    TITLE="Nonce Store Response Time - $START_TIME"
    TITLE="$TITLE: Concurrency = $CONCURRENCY"
    TITLE="$TITLE; ${PERCENTILE}th Percentile"
    gnuplot \
        -e "input_filename='$PERCENTILETEMPFILE'" \
        -e "output_filename='$RESULTS_FILE_BASE_NAME-09-nonce-store-response-time.png'" \
        -e "title='$TITLE'" \
        $SCRIPT_DIR_NAME/gp.cfg/yar_server_response_time

    TITLE="Nonce Store Response Time - $START_TIME"
    TITLE="$TITLE: Concurrency = $CONCURRENCY"
    TITLE="$TITLE; ${PERCENTILE}th Percentile"
    gnuplot \
        -e "input_filename='$PERCENTILETEMPFILE'" \
        -e "output_filename='$RESULTS_FILE_BASE_NAME-10-nonce-store-response-time-by-time-in-test.png'" \
        -e "title='$TITLE'" \
        $SCRIPT_DIR_NAME/gp.cfg/yar_server_response_time_by_time

    rm "$TEMPFILE"
    rm "$PERCENTILETEMPFILE"

    #
    # during the load test the auth service was making requests
    # to the app service. the statements below extract timing
    # information about the requests from the auth service's
    # log and then plots 2 different graphs of response times.
    #
    TEMPFILE=$(mktemp)
    cat $DOCKER_CONTAINER_DATA/Auth-Service-*/auth_service_log | \
        grep "App Service.*responded in [0-9]\+ ms$" | \
        awk 'BEGIN {FS = "\t"; OFS = "\t"}; { print int($1 / 1000), $5 }' | \
        sed -s "s/\tApp Service.*responded in /\t/g" |
        sed -s "s/[[:space:]]ms$//g" \
        > $TEMPFILE

    PERCENTILETEMPFILE=$(mktemp)
    generate_yar_server_log_file_percentile \
        $PERCENTILE \
        $TEMPFILE \
        $PERCENTILETEMPFILE

    TITLE="App Service Response Time - $START_TIME"
    TITLE="$TITLE: Concurrency = $CONCURRENCY"
    TITLE="$TITLE; ${PERCENTILE}th Percentile"
    gnuplot \
        -e "input_filename='$PERCENTILETEMPFILE'" \
        -e "output_filename='$RESULTS_FILE_BASE_NAME-11-app-service-response-time.png'" \
        -e "title='$TITLE'" \
        $SCRIPT_DIR_NAME/gp.cfg/yar_server_response_time

    TITLE="App Service Response Time - $START_TIME"
    TITLE="$TITLE: Concurrency = $CONCURRENCY"
    TITLE="$TITLE; ${PERCENTILE}th Percentile"
    gnuplot \
        -e "input_filename='$PERCENTILETEMPFILE'" \
        -e "output_filename='$RESULTS_FILE_BASE_NAME-12-app-service-response-time-by-time-in-test.png'" \
        -e "title='$TITLE'" \
        $SCRIPT_DIR_NAME/gp.cfg/yar_server_response_time_by_time

    rm -f $PERCENTILETEMPFILE >& /dev/null
    rm -f $TEMPFILE >& /dev/null

    #
    # metrics graphing ... cpu ...
    #
    gen_cpu_usage_graph \
        "Auth Service Load Balancer CPU Usage - $START_TIME: Concurrency = $CONCURRENCY" \
        "AUTH_SERVICE_LB_CONTAINER_ID" \
        "$RESULTS_FILE_BASE_NAME-20-auth-service-lb-cpu-usage.png"

    local AUTH_SERVICE_NUMBER=1
    for AUTH_SERVICE_CONTAINER_ID_KEY in $(get_all_auth_service_container_id_keys)
    do
        local GRAPH_TITLE="Auth Service # $AUTH_SERVICE_NUMBER CPU Usage"
        GRAPH_TITLE="$GRAPH_TITLE - $START_TIME: Concurrency = $CONCURRENCY"

        local GRAPH_FILENAME="$RESULTS_FILE_BASE_NAME-21-auth-service"
        GRAPH_FILENAME="$GRAPH_FILENAME-$AUTH_SERVICE_NUMBER-cpu-usage.png"

        gen_cpu_usage_graph \
            "$GRAPH_TITLE" \
            "$AUTH_SERVICE_CONTAINER_ID_KEY" \
            "$GRAPH_FILENAME"

        let "AUTH_SERVICE_NUMBER += 1"
    done

    gen_cpu_usage_graph \
        "Key Service Load Balancer CPU Usage - $START_TIME: Concurrency = $CONCURRENCY" \
        "KEY_SERVICE_LB_CONTAINER_ID" \
        "$RESULTS_FILE_BASE_NAME-21-key-service-lb-cpu-usage.png"

    local KEY_SERVICE_NUMBER=1
    for KEY_SERVICE_CONTAINER_ID_KEY in $(get_all_key_service_container_id_keys)
    do
        local GRAPH_TITLE="Key Service # $KEY_SERVICE_NUMBER CPU Usage"
        GRAPH_TITLE="$GRAPH_TITLE - $START_TIME: Concurrency = $CONCURRENCY"

        local GRAPH_FILENAME="$RESULTS_FILE_BASE_NAME-22-key-service"
        GRAPH_FILENAME="$GRAPH_FILENAME-$KEY_SERVICE_NUMBER-cpu-usage.png"

        gen_cpu_usage_graph \
            "$GRAPH_TITLE" \
            "$KEY_SERVICE_CONTAINER_ID_KEY" \
            "$GRAPH_FILENAME"

        let "KEY_SERVICE_NUMBER += 1"
    done

    gen_cpu_usage_graph \
        "Key Store CPU Usage - $START_TIME: Concurrency = $CONCURRENCY" \
        "KEY_STORE_CONTAINER_ID" \
        "$RESULTS_FILE_BASE_NAME-23-key-store-cpu-usage.png"

    local NONCE_STORE_NUMBER=1
    for NONCE_STORE_CONTAINER_ID_KEY in $(get_all_nonce_store_container_id_keys)
    do
        local GRAPH_TITLE="Nonce Store # $NONCE_STORE_NUMBER CPU Usage"
        GRAPH_TITLE="$GRAPH_TITLE - $START_TIME: Concurrency = $CONCURRENCY"

        local GRAPH_FILENAME="$RESULTS_FILE_BASE_NAME-24-nonce-store"
        GRAPH_FILENAME="$GRAPH_FILENAME-$NONCE_STORE_NUMBER-cpu-usage.png"

        gen_cpu_usage_graph \
            "$GRAPH_TITLE" \
            "$NONCE_STORE_CONTAINER_ID_KEY" \
            "$GRAPH_FILENAME"

        let "NONCE_STORE_NUMBER += 1"
    done

    gen_cpu_usage_graph \
        "App Service Load Balancer CPU Usage - $START_TIME: Concurrency = $CONCURRENCY" \
        "APP_SERVICE_LB_CONTAINER_ID" \
        "$RESULTS_FILE_BASE_NAME-25-app-service-lb-cpu-usage.png"

    local APP_SERVICE_NUMBER=1
    for APP_SERVICE_CONTAINER_ID_KEY in $(get_all_app_service_container_id_keys)
    do
        local GRAPH_TITLE="App Service # $APP_SERVICE_NUMBER CPU Usage"
        GRAPH_TITLE="$GRAPH_TITLE - $START_TIME: Concurrency = $CONCURRENCY"

        local GRAPH_FILENAME="$RESULTS_FILE_BASE_NAME-26-app-service"
        GRAPH_FILENAME="$GRAPH_FILENAME-$APP_SERVICE_NUMBER-cpu-usage.png"

        gen_cpu_usage_graph \
            "$GRAPH_TITLE" \
            "$APP_SERVICE_CONTAINER_ID_KEY" \
            "$GRAPH_FILENAME"

        let "APP_SERVICE_NUMBER += 1"
    done

    #
    # metrics graphing ... memory ...
    #
    gen_mem_usage_graph \
        "Auth Service Load Balancer Memory Usage - $START_TIME: Concurrency = $CONCURRENCY" \
        "AUTH_SERVICE_LB_CONTAINER_ID" \
        "$RESULTS_FILE_BASE_NAME-30-auth-service-lb-memory-usage.png"

    local AUTH_SERVICE_NUMBER=1
    for AUTH_SERVICE_CONTAINER_ID_KEY in $(get_all_auth_service_container_id_keys)
    do
        local GRAPH_TITLE="Auth Service # $AUTH_SERVICE_NUMBER Memory Usage"
        GRAPH_TITLE="$GRAPH_TITLE - $START_TIME: Concurrency = $CONCURRENCY"

        local GRAPH_FILENAME="$RESULTS_FILE_BASE_NAME-31-auth-service"
        GRAPH_FILENAME="$GRAPH_FILENAME-$AUTH_SERVICE_NUMBER-memory-usage.png"

        gen_mem_usage_graph \
            "$GRAPH_TITLE" \
            "$AUTH_SERVICE_CONTAINER_ID_KEY" \
            "$GRAPH_FILENAME"

        let "AUTH_SERVICE_NUMBER += 1"
    done

    gen_mem_usage_graph \
        "Key Service Load Balancer Memory Usage - $START_TIME: Concurrency = $CONCURRENCY" \
        "KEY_SERVICE_LB_CONTAINER_ID" \
        "$RESULTS_FILE_BASE_NAME-32-key-service-lb-memory-usage.png"

    local KEY_SERVICE_NUMBER=1
    for KEY_SERVICE_CONTAINER_ID_KEY in $(get_all_key_service_container_id_keys)
    do
        local GRAPH_TITLE="Key Service # $KEY_SERVICE_NUMBER Memory Usage"
        GRAPH_TITLE="$GRAPH_TITLE - $START_TIME: Concurrency = $CONCURRENCY"

        local GRAPH_FILENAME="$RESULTS_FILE_BASE_NAME-33-auth-service"
        GRAPH_FILENAME="$GRAPH_FILENAME-$KEY_SERVICE_NUMBER-memory-usage.png"

        gen_mem_usage_graph \
            "$GRAPH_TITLE" \
            "$KEY_SERVICE_CONTAINER_ID_KEY" \
            "$GRAPH_FILENAME"

        let "KEY_SERVICE_NUMBER += 1"
    done

    gen_mem_usage_graph \
        "Key Store Memory Usage - $START_TIME: Concurrency = $CONCURRENCY" \
        "KEY_STORE_CONTAINER_ID" \
        "$RESULTS_FILE_BASE_NAME-34-key-store-memory-usage.png"

    local NONCE_STORE_NUMBER=1
    for NONCE_STORE_CONTAINER_ID_KEY in $(get_all_nonce_store_container_id_keys)
    do
        local GRAPH_TITLE="Nonce Store # $NONCE_STORE_NUMBER Memory Usage"
        GRAPH_TITLE="$GRAPH_TITLE - $START_TIME: Concurrency = $CONCURRENCY"

        local GRAPH_FILENAME="$RESULTS_FILE_BASE_NAME-35-nonce-store"
        GRAPH_FILENAME="$GRAPH_FILENAME-$NONCE_STORE_NUMBER-memory-usage.png"

        gen_mem_usage_graph \
            "$GRAPH_TITLE" \
            "$NONCE_STORE_CONTAINER_ID_KEY" \
            "$GRAPH_FILENAME"

        let "NONCE_STORE_NUMBER += 1"
    done

    gen_mem_usage_graph \
        "App Service Load Balancer Memory Usage - $START_TIME: Concurrency = $CONCURRENCY" \
        "APP_SERVICE_LB_CONTAINER_ID" \
        "$RESULTS_FILE_BASE_NAME-36-app-service-lb-memory-usage.png"

    local APP_SERVICE_NUMBER=1
    for APP_SERVICE_CONTAINER_ID_KEY in $(get_all_app_service_container_id_keys)
    do
        local GRAPH_TITLE="App Service # $APP_SERVICE_NUMBER Memory Usage"
        GRAPH_TITLE="$GRAPH_TITLE - $START_TIME: Concurrency = $CONCURRENCY"

        local GRAPH_FILENAME="$RESULTS_FILE_BASE_NAME-37-app-service"
        GRAPH_FILENAME="$GRAPH_FILENAME-$APP_SERVICE_NUMBER-memory-usage.png"

        gen_mem_usage_graph \
            "$GRAPH_TITLE" \
            "$APP_SERVICE_CONTAINER_ID_KEY" \
            "$GRAPH_FILENAME"

        let "APP_SERVICE_NUMBER += 1"
    done

	local NONCE_STORE_NUMBER=1
	for NSEP in $(get_all_nonce_store_end_points); do
		IP=$(echo $NSEP | sed -e "s/:.*$//")

        local GRAPH_TITLE="Nonce Store # $NONCE_STORE_NUMBER Key Metrics"
        GRAPH_TITLE="$GRAPH_TITLE - $START_TIME: Concurrency = $CONCURRENCY"

        local GRAPH_FILENAME="$RESULTS_FILE_BASE_NAME-40-nonce-store"
        GRAPH_FILENAME="$GRAPH_FILENAME-$NONCE_STORE_NUMBER-key-metrics.png"

		gen_nonce_store_graph \
			"$GRAPH_TITLE" \
			"$IP" \
			"$GRAPH_FILENAME"

        let "NONCE_STORE_NUMBER += 1"
	done
}

#
# this is where the test's mainline really begins
#
SCRIPT_DIR_NAME="$( cd "$( dirname "$0" )" && pwd )"
source $SCRIPT_DIR_NAME/../util.sh
source $SCRIPT_DIR_NAME/util.sh

#
# parse command line arguments
#
VERBOSE=0
TEST_PROFILE=""

while [[ 0 -ne $# ]]
do
    KEY="$1"
    shift
    case $KEY in
        -v|--verbose)
            VERBOSE=1
            ;;
        -p|--profile)
            TEST_PROFILE=${1:-}
            shift
            ;;
        *)
            echo_to_stderr "usage: `basename $0` [-v] [-p <test profile>]"
            exit 1
            ;;
    esac
done

#
# if a test profile was not specified via the --profile command line
# argument then create a reasonable default test profile
#
if [ "$TEST_PROFILE" == "" ]; then
    TEST_PROFILE=$(platform_safe_mktemp)
    echo '{'                               >> $TEST_PROFILE
    echo '    "concurrency": [5],'         >> $TEST_PROFILE
    echo '    "number_of_requests": 1000,' >> $TEST_PROFILE
    echo '    "percentile": 99.9'          >> $TEST_PROFILE
    echo '}'                               >> $TEST_PROFILE

    echo_if_verbose "No test profile specified - using default - see test report for details"
else
    if [ ! -r $TEST_PROFILE ]; then
        echo_to_stderr "Could not read test profile '$TEST_PROFILE'"
        exit 1
    fi
fi

#
# load test setup isn't totally straight forward so do a little
# poking around to see if there's anything that might be an indication
# of why a load test might fail
# 
if ! ls $SCRIPT_DIR_NAME/../lots-of-creds/*.couch >& /dev/null; then
    echo_if_verbose "Couldn't find any .couch files in '$SCRIPT_DIR_NAME/../lots-of-creds'"
    echo_if_verbose "-- Might have trouble starting Key Store"
    echo_if_verbose "-- or Key Store might take long time to start"
    echo_if_verbose "-- if .couch files are downloaded."
fi

#
# little bit of pre-test setup ...
#
START_TIME=$(date +%Y-%m-%d-%H-%M)

RESULTS_DIR=$SCRIPT_DIR_NAME/test-results/$START_TIME
mkdir -p $RESULTS_DIR

#
# run the load test at various concurrency levels
#
for i in {0..100}   # assuming 100 different concurrency levels is enough?
do
    CONCURRENCY=`get_from_json "\[\"concurrency\"\,$i\]" "" < $TEST_PROFILE`
    if [ "$CONCURRENCY" == "" ]; then
        break
    fi
    run_load_test $TEST_PROFILE $CONCURRENCY $RESULTS_DIR
done

#
# generate the title page and last page of the summary report
#
convert \
    -background lightgray \
    -fill black \
    -size 3200x1800 \
    label:"yar load test ($START_TIME)" \
    -gravity center \
    $RESULTS_DIR/0000.png

convert \
    -background lightgray \
    -fill black \
    -size 3200x1800 \
    label:"End of Report" \
    -gravity center \
    $RESULTS_DIR/9999.png

#
# generate the summary report
#
# used to just do a
#
#   convert $RESULTS_DIR/*.png $SUMMARY_REPORT_FILENAME
#
# but convert started to fail (think when the number/size
# of pngs pushed past some limit).
#
rm -f $RESULTS_DIR/*.pdf

for PNG in $RESULTS_DIR//*.png
do
    PNG_AS_PDF=$(echo "$PNG" | sed -e "s/png$/pdf/")
    convert $PNG $PNG_AS_PDF
    # gs -q -o /dev/null -sDEVICE=nullpage $PNG_AS_PDF
done

SUMMARY_REPORT_FILENAME=$RESULTS_DIR/test-results-summary
gs \
    -dBATCH \
    -dNOPAUSE \
    -q \
    -sDEVICE=pdfwrite \
    -sOutputFile="$SUMMARY_REPORT_FILENAME" \
    $RESULTS_DIR/*.pdf

rm -f $RESULTS_DIR/*.pdf

mv "$SUMMARY_REPORT_FILENAME" "$SUMMARY_REPORT_FILENAME.pdf"

#
# all done, just let folks know where to find the results
#
echo "Complete results in '$RESULTS_DIR'"
echo "Summary report '$SUMMARY_REPORT_FILENAME'"

exit 0


GPUID=-1 #set this to something >= 0 to use the GPU

torch_gpu_id=0 #torch always thinks it's running on GPUID 0, but the CUDA_VISIBLE_DEVICES environment variable (set below) changes what that means.
if [ "$GPUID" == -1 ]; then
	torch_gpu_id=-1
fi

d=tag-runs/`date | sed 's| |_|g'`
log=$d/log.txt
mkdir -p $d

results_file_dir=$d/results
mkdir $results_file_dir


#Use the synthetic training data generated by test/test_data_serialization_and_loading.lua
echo ./data/sequence/crf-data.train > ./data/sequence/crf-data.train.list
echo ./data/sequence/crf-data.test > ./data/sequence/crf-data.test.list


#These options are for restoring stuff from previous runs
#Restore the local classifier (features and 'local potentials')
#init_classifier=  # for example, $previous_run_dir/model--pretrain_unaries.50.classifier
#iC="-init_classifier $init_classifier"

#Restore a full unrolled network for gradient-based prediction
#init_full_net=   # for example, $previous_run_dir/model--update_all.50.predictor
#iF="-init_full_net $init_full_net"

#Restore the optimization state of a previous run
#init_opt_state=  # for example, $previous_run_dir/model--update_all.50.opt_state
#iO="-init_opt_state $init_opt_state"

data_options="-train_list ./data/sequence/crf-data.train.list -test_list ./data/sequence/crf-data.test.list  -out_dir $results_file_dir -model_file $d/model- $iC $iF $iO"
system_options=" -batch_size 10  -gpuid $torch_gpu_id -profile 0 "

problem_config=$d/problem-config 
problem_options="-problem_config $problem_config"

#These are the only options that are specific to the problem domain and architecture
problem_options_str="" #just using default values for now
th flags/SequenceTaggingOptions.lua $problem_options_str -serialize $problem_config
problem_options="$problem_options -problem SequenceTagging"

inference_options="-init_at_local_prediction 0 -inference_learning_rate 0.1 -max_inference_iters 20  -inference_learning_rate_decay 0 -inference_momentum 0.5 -learn_inference_hyperparams 1 -unconstrained_iterates 1"


general_training_options="-training_method E2E"
base_training_config="-gradient_clip 1.0 -optim_method adam -evaluation_frequency 25 -save_frequency 25  -adam_epsilon 1e-8 -batches_per_epoch 100 -learning_rate_decay 0.0"


pretrain_configs="$base_training_config -learning_rate 0.001 -num_epochs 30 -training_mode pretrain_unaries"
first_pass_configs="$base_training_config -learning_rate 0.001 -num_epochs 100 -training_mode clamp_features"
second_pass_configs="$base_training_config -learning_rate 0.0005 -num_epochs 500 -training_mode update_all"

#This packages up lua tables for the options that are specific to the different stages of training.
training_config=$d/train-config
echo $pretrain_configs
th flags/TrainingOptions.lua $pretrain_configs -serialize $training_config.0
th flags/TrainingOptions.lua $first_pass_configs -serialize $training_config.1
th flags/TrainingOptions.lua $second_pass_configs -serialize $training_config.2
echo $training_config.{0,1,2} | tr ' ' '\n' > $training_config
training_options="-training_configs $training_config"

cmd="th main.lua $data_options $system_options $problem_options $inference_options $training_options $general_training_options"

echo echo running in $d > $d/cmd.sh   
echo export CUDA_VISIBLE_DEVICES=$GPUID >> $d/cmd.sh                                                                                                                                                                                                

echo $cmd >> $d/cmd.sh                                                                               
sh $d/cmd.sh 2>&1 |  tee $log  | tee latest-run.log


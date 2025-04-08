#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>

#include <gsl/gsl_rng.h>
#include <gsl/gsl_randist.h>
#include <gsl/gsl_vector.h>
#include <gsl/gsl_blas.h>
#include <gsl/gsl_multimin.h>
#include <gsl/gsl_multifit_nlin.h>

/**
 * Colors code for printing
 */
#define KNRM  "\x1B[0m"
#define KRED  "\x1B[31m"
#define KGRN  "\x1B[32m"
#define KYEL  "\x1B[33m"
#define KBLU  "\x1B[34m"
#define KMAG  "\x1B[35m"
#define KCYN  "\x1B[36m"
#define KWHT  "\x1B[37m"

#define eul 2.71828182845905
#define pi 3.14159265358979

#ifndef MAX
#define MAX(x, y) (((x) > (y)) ? (x) : (y))
#endif
#ifndef MIN
#define MIN(x, y) (((x) < (y)) ? (x) : (y))
#endif

typedef struct Individual{
	
	double *params;						/*!< Stores inidividual's parameters */
	double mean_cost;					/*!< Stores the mean of current Individual's cost until its randomization */
	double var_cost;					/*!< Stores the variance of current Individual's cost until its randomization */
	double cost;						/*!< Stores the cost of current Individual */
	double dist;						/*!< Stores the distance of current Individual to a set of other Individuals */

	int n_not_randomized;				/*!< Stores the number of times that the specific Individual updates but not randomize. It will be used to update the stats */
	int n_stuck;						/*!< Stores the number of times that the specific Individual hasn't been updated during the optimization process. */

} Individual;

typedef struct Set{
	
	Individual *members;				/*!< Array of Individuals */
	double mean_cost;					/*!< mean cost of all the Individual in the current set */
	double std_cost;					/*!< standard deviation of cost of all Individuals in the current set. This could be used to stop the algorithm if the refSet is  */
	double *params_means;				/*!< Stores the mean values of each parameters in the set among all the Individuals */
	int size;							/*!< Size of the set */

} Set;

typedef struct Stats{

	int n_successful_goBeyond;
	int n_local_search_performed;
	int n_successful_localSearch;
	int n_local_search_iterations;
	int n_total_stuck;
	int n_successful_recombination;
	int n_refSet_randomized;
	int n_duplicate_found;
	int n_flatzone_detected;

	int **freqs_matrix;
	double **probs_matrix;
} Stats;


typedef struct eSSType{

	/********************************************************************************************
	 * Global Options
	 */
	int n_params;
	int n_datapoints;					/*!< Stores the number of datapoints for performing the efficient least-square optimizations. */
	
	int max_stuck;						/*!< Maximum number allowed for an individual to be stuck; if ind->n_stuck exceed this value, individual will be randomized. */
	int max_eval;						/*!< Maximum number of function evaluation before stop */
	int max_time;						/*!< Maximum CPU time before stop */
	int max_iter;						/*!< Maximum iteration before stop */


	bool perform_elite_preservation; 	/*!< Indicates if the algorithm should preserve some elite in the refSet during the optimization regardless of their n_stuck values. */
	int max_preserve_elite;				/*!< Indicates how many of the elite memebers should not randomize during the process. */

	int iter;							/*!< Store the generation number */

	int max_delete;						/*!< Specify the number of Individual that should be deleted during the randomization of the refSet. */

	double *min_real_var;				/*!< Stores `lowerbound` of parameters */
	double *max_real_var;				/*!< Stores `upperbound` of parameters */

	int n_sub_regions;					/*!< Number of sub-regions which will be used during initialization of scatterSet */
	double **min_boundary_matrix;		/*!< Stores `lowerbound` of sub-regions for each parameter, only uses for creating `scatterSet` */
	double **max_boundary_matrix;		/*!< Stores `upperbound` of sub-regions for each parameter, only uses for creating `scatterSet` */
	
	double sol;							/*!< Stores possible minimum cost for performing convergence test. */
	
	bool logBound;
	double prob_bound;

	int goBeyond_freqs;					/*!< Frequency of performing goBeyond procedure */

	int perform_refSet_randomization;	/*!< Randomize the refSet if the standard deviation of the set's cost is below some threshold. NOTE: The compute_Set_Stats flag should be ON to compute the necessary information for this operation. */
	int n_randomization_Freqs;			/*!< The frequency of randomizing stuck refSet members, this somehow increase the max_stuck value and give some solution some extra chance to escape the local minimum. */

	/********************************************************************************************
	 * IO, Reports Parameters
	 */
	bool debug;
	bool log;
	bool init_with_user_guesses;	/*!< Indicates if the refSet should fill with user initial guesses or not */
	int print_freqs;						/*!< Frequency of printing the output including the stats, refSet, and bestSol. */
	bool save_output;					/*!< Indicates if the program should save outputs to file or not. */
	int save_freqs;
	bool perform_warm_start;						/*!< Indicates if the algorithm should start with a stored refSet. If it's `true`, program will look for `ref_set_final.csv` and initializes refSet with that. */
	bool plot;							/*!< Indicates if the result should be plotted or not. */
	
	
	/********************************************************************************************
	 * Sets
	 */
	int n_refSet;						/*!< Reference Set size, can be set or computed automacitally. */
	Set *refSet;
	
	int n_scatterSet;					/*!< Scatter Set size, computed automaticall. */
	Set *scatterSet;

	int n_childsSet;
	Set *childsSet;						/*!< Stores best members of recombinedSet for each refSet member, size: n_refSet. `label` variable indidcates indices that has a new values during the iterations. */

	int n_candidateSet;
	Set *candidateSet;					/*!< Stores childs generated from each refSet in each generation, size: n_refSet - 1 */

	int n_localSearch_Candidate;
	Set *localSearchCandidateSet;

	int n_archiveSet;					/*!< Store the size of archiveSet */
	Set *archiveSet;					/*!< Use for storing the stuck solutions in the refSet. */

	Individual *best;					/*!< Pointer to the first member of refSet which is always the best sol */

	// int diversification_Type;


	/********************************************************************************************
	 * Tolerances
	 */
	int perform_cost_tol_stopping;
	double cost_tol;				/*!< Cost Tolerance for stopping */

	int perform_flatzone_check;
	double flatzone_coef;			/*!< flatzone_coef uses to compute the flatzone interval */

	int equality_type;				/*!< Specify how the equality of two Individuals should be computed, either by the closeness of its parameters (1) or by euclidean distance between two Individuals (0) */
	double euclidean_dist_tol;		/*!< Minimum euclidean distance of two individuals to be considered the same. */		
	double param_diff_tol;			/*!< Minimum difference between two parameters of an individual to be consider the same. */

	double refSet_std_tol;					/*!< Tolerance value for the standard deviation of a set to perform the randomization; randomize the set if the standard_deviation of refSet is below this value. By randomization, we mean deleting `max_delete` worst results in the refSet and replace them with new individuals. */

	// int perform_refSet_convergence_stopping;	/*!< Experimental flag to check the convergence of refSet by comparing the bestSol->cost and worstSol->cost */
	// double refSet_convergence_tol;		
	
	/********************************************************************************************
	 * Local Search Options
	 */
	
	bool perform_local_search;
	char local_SolverMethod;		/*!< Local search method, `l`: Levenberg-Marquardt, 'n': Nelder-Mead (Intensification Method) */
	double *weight;						/*!< Parameters importance weights to be used by Levenberg method. */

	double local_minCostCriteria;	/*!< Indicates minimum cost criteria to perform local search */
	int local_maxIter;				/*!< Maximum iterations of the local search algorithm in each run */
	double local_tol;				/*!< Local search convergence tolerance */
	int local_N1;					/*!< Starting the local search after local_N1 iterations */
	int local_N2;					/*!< Frequency of local search after first local_N1 iterations --> Intensification Frequency */ 
	bool local_atEnd;				/*!< Indicates if the local_search should only be applied at the end of the search */
	bool local_onBest_Only;			/*!< Indicates if the local search should be only applied on the bestSol during the search */
	double local_Balance;			/*!< Balance between the diversity and quality for choosing the initial point for local search, NOTE: It's not implemented yet! */
	
	// int local_merit_Filter;
	// int local_distance_Filter;
	// double local_th_merit_Factor;
	// double local_max_distance_Factor;
	// int local_wait_maxDist_limit;
	// int local_wait_th_limit;

	/********************************************************************************************
	 * Statistics
	 */
	Stats *stats;					/*!< Storing different statistics durig the running, check `struct Stats` */
	bool collect_stats;					/*!< Indicates if the algorithm should compute statistics or not. */
	bool compute_Ind_Stats;			/*!< Flag that indicates if Individuals should compute and store their statistics */ 
	bool compute_Set_Stats;			/*!< Flag that indicates if a set should computes and stores its statistics */


	/********************************************************************************************
	 * Not implemented parameters
	 */
	int refSet_init_method;					/*!< */
	int combination_method;					/*!< */
	int regeneration_method;				/*!< */
	

} eSSType;



/**
 * Gloabl output files...
 */
extern FILE *refSet_history_file;
extern FILE *best_sols_history_file;
extern FILE *freqs_matrix_file;
extern FILE *freq_mat_final_file;
extern FILE *prob_mat_final_file;
extern FILE *refSet_final_file;
extern FILE *stats_file;
extern FILE *ref_set_stats_history_file;
extern FILE *user_initial_guesses_file;
extern FILE *archive_set_file;


/**
 * essInit.c
 */
void init_defaultSettings(eSSType *eSSParams);
void init_essParams(eSSType*);
void init_scatterSet(eSSType*, void*, void*);
void init_refSet(eSSType*, void*, void*);
void init_report_files(eSSType *);
void init_stats(eSSType *);
void init_perform_warm_start(eSSType *);

/**
 * essStats.c
 */
void updateFrequencyMatrix(eSSType*);
void compute_Mean(eSSType*, Individual*);
void compute_Std(eSSType*, Individual*);
void compute_SetStats(eSSType*, Set*);
void update_IndsStats(eSSType *eSSParams, Set *set);
void update_IndStats(eSSType *, Individual *);

/**
 * essGoBeyond
 */
void goBeyond(eSSType*, int, void*, void*);

/**
 * essLocalSearch.c
 */
void localSearch(eSSType*, Individual*, void*, void*, char method);
int levmer_localSearch(eSSType *eSSParams, Individual *ind, void *inp, void *out);
int neldermead_localSearch(eSSType *eSSParams, Individual *ind, void *inp, void *out);

/**
 * essRecombine.c
 */
int recombine(eSSType*, Individual*, int, void*, void*);

/**
 * essSort.c
 */
void quickSort_Set(eSSType*, Set*, int, int, char);
void quickSort(eSSType*, Set*, double*, int, int);
void insertionSort(eSSType*, Set*, int, char);

/**
 * essAllocate.c
 */
void allocate_Ind(eSSType *, Individual *);
void deallocate_Ind(eSSType *, Individual *);
void allocate_Set(eSSType *, Set *);
void deallocate_Set(eSSType *, Set *);
void deallocate_eSSParams(eSSType *);


/**
 * essTools.c
 */
double euclidean_distance(eSSType*, Individual*, Individual*);
void isExist(eSSType*, Individual*);
double min(double*, int, int*);
double max(double*, int, int*);
void copy_Ind(eSSType *, Individual *, Individual *);
void delete_and_shift(eSSType *eSSParams, Set *set, int set_size, int index_to_delete);
int closest_member(eSSType *, Set *, int , Individual *, int );
int is_exist(eSSType *eSSParams, Set *set, Individual *ind);
bool is_equal_dist(eSSType *eSSParams, Individual *ind1, Individual *ind2);
bool is_equal_pairwise(eSSType *eSSParams, Individual *ind1, Individual *ind2);
bool is_in_flatzone(eSSType *eSSParams, Set *set, Individual *ind);

/**
 * essRand.c
 */
double rndreal(double, double);
void random_Set(eSSType*, Set*, double*, double* );
void random_Ind(eSSType*, Individual*, double*, double* );

/**
 * essProblem.c
 */
double objectiveFunction(eSSType*, Individual*, void*, void*);
void init_sampleParams(eSSType*);

double objfn(double []);
void bounds(double lb[], double ub[]);
int feasible(double x[]);
int levermed_objfn(const gsl_vector *x, void *data, gsl_vector *f);
double nelder_objfn(const gsl_vector *x, void *data);


/**
 * Benchmark functions prototype
 */
void bounds(double lb[], double ub[]);
int feasible(double x[]);
double objfn(double x[]);
double nelder_objfn(const gsl_vector *x, void *data);


/**
 * essEvaluate.c
 */
void evaluate_Individual(eSSType*, Individual*, void*, void*);
void evaluate_Set(eSSType*, Set*, void*, void*);

/**
 * ess.c
 */
void init_eSS(eSSType*, void*, void*);
void run_eSS(eSSType*, void*, void*);


/**
 * essIO.c
 */
void read_cli_params(eSSType *, int, char **);
void print_eSSParams(eSSType*);
void print_Set(eSSType*, Set*);
void print_Ind(eSSType*, Individual*);
void write_Set(eSSType*, Set*, FILE*, int);
void write_Ind(eSSType*, Individual*, FILE*, int);
void print_Stats(eSSType *);
void write_Stats(eSSType *, FILE *);
void parse_double_row(eSSType *eSSParams, char *line, double *row);
void parse_int_row(eSSType *eSSParams, char *line, int *row);
void print_Inputs(eSSType *);

/**
 * essMain.c
 */





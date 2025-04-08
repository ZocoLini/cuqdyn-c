#include "ess.h"

void evaluate_Individual(eSSType *eSSParams, Individual *ind, void *inp, void *out){

	ind->cost = objectiveFunction(eSSParams, ind, inp, out);
	// print_Ind(eSSParams, ind);
}

void evaluate_Set(eSSType *eSSParams, Set *set, void *inp, void *out){

	for (int i = 0; i < set->size; ++i)
	{
		evaluate_Individual(eSSParams, &(set->members[i]), inp, out);
	}
}
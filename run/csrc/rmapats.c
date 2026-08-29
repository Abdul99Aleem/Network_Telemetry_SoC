// file = 0; split type = patterns; threshold = 100000; total count = 0.
#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include "rmapats.h"

void  schedNewEvent (struct dummyq_struct * I1403, EBLK  * I1398, U  I624);
void  schedNewEvent (struct dummyq_struct * I1403, EBLK  * I1398, U  I624)
{
    U  I1667;
    U  I1668;
    U  I1669;
    struct futq * I1670;
    struct dummyq_struct * pQ = I1403;
    I1667 = ((U )vcs_clocks) + I624;
    I1669 = I1667 & ((1 << fHashTableSize) - 1);
    I1398->I666 = (EBLK  *)(-1);
    I1398->I667 = I1667;
    if (0 && rmaProfEvtProp) {
        vcs_simpSetEBlkEvtID(I1398);
    }
    if (I1667 < (U )vcs_clocks) {
        I1668 = ((U  *)&vcs_clocks)[1];
        sched_millenium(pQ, I1398, I1668 + 1, I1667);
    }
    else if ((peblkFutQ1Head != ((void *)0)) && (I624 == 1)) {
        I1398->I669 = (struct eblk *)peblkFutQ1Tail;
        peblkFutQ1Tail->I666 = I1398;
        peblkFutQ1Tail = I1398;
    }
    else if ((I1670 = pQ->I1306[I1669].I689)) {
        I1398->I669 = (struct eblk *)I1670->I687;
        I1670->I687->I666 = (RP )I1398;
        I1670->I687 = (RmaEblk  *)I1398;
    }
    else {
        sched_hsopt(pQ, I1398, I1667);
    }
}
#ifdef __cplusplus
extern "C" {
#endif
void SinitHsimPats(void);
#ifdef __cplusplus
}
#endif

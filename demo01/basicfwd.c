/* SPDX-License-Identifier: BSD-3-Clause
 * Copyright(c) 2021 Intel Corporation
 */

#include <stdint.h>
#include <inttypes.h>
#include <rte_eal.h>
#include <rte_ethdev.h>
#include <rte_cycles.h>
#include <rte_lcore.h>
#include <rte_mbuf.h>

int
main(int argc, char *argv[])
{

        /* Step 01: Initialize the Environment Abstraction Layer (EAL). */
        int ret = rte_eal_init(argc, argv);
        if (ret < 0)
           rte_exit(EXIT_FAILURE, "Error on rte_eal_init\n");

        /* Step 02: Get Available Ports. */
        unsigned nb_ports = rte_eth_dev_count_avail();
        if (nb_ports < 2 || (nb_ports & 1)){
            char *port_example  = "./build/testapp -- -p 0x3";
            rte_exit(EXIT_FAILURE, "Error port number, the defined port number is %d.\n" 
                                       "Required at least 2 or even number of ports defined.\n\ne.g. %s\n\n"
					,nb_ports,port_example);
        }

       /* Step 03: Creates a new mempool in memory to hold the mbufs. */
       unsigned socket_cnt = rte_socket_count();
       unsigned socket_id = rte_socket_id();
       //printf("\n\nsocket count=%d id=%d",socket_cnt,socket_id);
       const int nb_mbufs = 8191;
       const int sz_cache = 250;
       struct rte_mempool *mbuf_pool = rte_pktmbuf_pool_create("MBUF_POOL", nb_mbufs * nb_ports, sz_cache, 0, RTE_MBUF_DEFAULT_BUF_SIZE, socket_id);
       if (mbuf_pool == NULL)
		rte_exit(EXIT_FAILURE, "Cannot create mbuf pool\n"); 

       /* Step 04: Configuring each ports */
       uint16_t portid;
       RTE_ETH_FOREACH_DEV(portid){
            printf("\n\nport id=%d\n" , portid);
       }

       /* Step 05: Display core information */
       int ttl_core = rte_lcore_count(); 
       printf("\n\ntotal of core dedicsted for  dpdk=%d\n\n", ttl_core);

       return 0;
}


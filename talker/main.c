/* SPDX-License-Identifier: BSD-3-Clause
 * Copyright(c) 2010-2021 Intel Corporation
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include <sys/types.h>
#include <sys/queue.h>
#include <netinet/in.h>
#include <setjmp.h>
#include <stdarg.h>
#include <ctype.h>
#include <errno.h>
#include <getopt.h>
#include <signal.h>
#include <stdbool.h>
#include <unistd.h>

#include <rte_common.h>
#include <rte_log.h>
#include <rte_malloc.h>
#include <rte_memory.h>
#include <rte_memcpy.h>
#include <rte_eal.h>
#include <rte_launch.h>
#include <rte_atomic.h>
#include <rte_cycles.h>
#include <rte_prefetch.h>
#include <rte_lcore.h>
#include <rte_per_lcore.h>
#include <rte_branch_prediction.h>
#include <rte_interrupts.h>
#include <rte_random.h>
#include <rte_debug.h>
#include <rte_ether.h>
#include <rte_ethdev.h>
#include <rte_mempool.h>
#include <rte_mbuf.h>
#include <rte_string_fns.h>

#include <sys/time.h>

static volatile bool force_quit;

/* MAC updating enabled by default */
static int mac_updating = 1;

static int iCounter = 0;

#define RTE_LOGTYPE_L2FWD RTE_LOGTYPE_USER1

#define MAX_PKT_BURST 32
#define BURST_TX_DRAIN_US 100 /* TX drain every ~100us */
#define MEMPOOL_CACHE_SIZE 256

/*
 * Configurable number of RX/TX ring descriptors
 */
#define RTE_TEST_RX_DESC_DEFAULT 1024
#define RTE_TEST_TX_DESC_DEFAULT 1024
static uint16_t nb_rxd = RTE_TEST_RX_DESC_DEFAULT;
static uint16_t nb_txd = RTE_TEST_TX_DESC_DEFAULT;

/* ethernet addresses of ports */
static struct rte_ether_addr l2fwd_ports_eth_addr[RTE_MAX_ETHPORTS];

/* mask of enabled ports */
static uint32_t l2fwd_enabled_port_mask = 0;

/* list of enabled ports */
static uint32_t l2fwd_dst_ports[RTE_MAX_ETHPORTS];

struct port_pair_params {
#define NUM_PORTS	2
	uint16_t port[NUM_PORTS];
} __rte_cache_aligned;

static struct port_pair_params port_pair_params_array[RTE_MAX_ETHPORTS / 2];
static struct port_pair_params *port_pair_params;
static uint16_t nb_port_pair_params;

static unsigned int l2fwd_rx_queue_per_lcore = 1;

#define MAX_RX_QUEUE_PER_LCORE 16
#define MAX_TX_QUEUE_PER_PORT 16
struct lcore_queue_conf {
	unsigned n_rx_port;
	unsigned rx_port_list[MAX_RX_QUEUE_PER_LCORE];
} __rte_cache_aligned;
struct lcore_queue_conf lcore_queue_conf[RTE_MAX_LCORE];

static struct rte_eth_dev_tx_buffer *tx_buffer[RTE_MAX_ETHPORTS];

static struct rte_eth_conf port_conf = {
	.rxmode = {
		.split_hdr_size = 0,
	},
	.txmode = {
		.mq_mode = ETH_MQ_TX_NONE,
	},
};

struct rte_mempool * l2fwd_pktmbuf_pool = NULL;

/* Per-port statistics struct */
struct l2fwd_port_statistics {
	uint64_t tx;
	uint64_t rx;
	uint64_t dropped; 
} __rte_cache_aligned;
struct l2fwd_port_statistics port_statistics[RTE_MAX_ETHPORTS];

#define MAX_TIMER_PERIOD 86400 /* 1 day max */

/* Interval of sending packet  */
static uint64_t pkt_interval = 20; /* default period is 20 miliseconds */


#define NSEC_PER_SEC 1000000000L


/*Destination mac address*/
static uint8_t dst_mac_addr[6] = {0x00,0x00,0x00,0x00,0x00,0x00};

static int is_debug =1;
static void debug0(const char* format,...){

  if (is_debug==0) return;

  char buffer[1000];
  va_list args;
  va_start (args, format);
  vsnprintf (buffer, 999, format, args);
  printf ("%s",buffer);
  va_end(args);

}


static void
l2fwd_mac_updating(struct rte_mbuf *m, unsigned dest_portid)
{
	struct rte_ether_hdr *eth;
	void *tmp;

	eth = rte_pktmbuf_mtod(m, struct rte_ether_hdr *);

	/* 02:00:00:00:00:xx */
	tmp = &eth->d_addr.addr_bytes[0];
	*((uint64_t *)tmp) = 0x000000000002 + ((uint64_t)dest_portid << 40);

	/* src addr */
	rte_ether_addr_copy(&l2fwd_ports_eth_addr[dest_portid], &eth->s_addr);
}

static void
l2fwd_simple_forward(struct rte_mbuf *m, unsigned portid)
{
	unsigned dst_port;
	int sent;
	struct rte_eth_dev_tx_buffer *buffer;


	dst_port = l2fwd_dst_ports[portid];
        //printf("\ndst_port id =%d", dst_port);

	if (mac_updating)
		l2fwd_mac_updating(m, dst_port);

	buffer = tx_buffer[dst_port];
	sent = rte_eth_tx_buffer(dst_port, 0, buffer, m);
	if (sent)
		port_statistics[dst_port].tx += sent;
}

static uint64_t get_time_nanosec(clockid_t clkid)
{

	struct timespec now;
	clock_gettime(clkid, &now);
	return now.tv_sec * NSEC_PER_SEC + now.tv_nsec;
}

static uint64_t get_time_nanosec_hwtsp(int port)
{

	uint64_t ticks;
	rte_eth_read_clock(port, &ticks);
	return ticks;

}

static int idx = 0;
static int  construct_packet(struct rte_mbuf *pkt[], const int pkt_size)
{
#define TIME_STAMP_MSG_SIZE 36  
#define VLAN_ID 3



        struct Message {
		char data[TIME_STAMP_MSG_SIZE];
 
	};
	struct rte_ether_hdr *eth_hdr;


        uint64_t tx_tsp  = get_time_nanosec(CLOCK_REALTIME); 
        //uint64_t tx_tsp  = get_time_nanosec_hwtsp(0); //hardware timestamp

        debug0("\nclock_gettime %"PRIu64
               ",idx %d", tx_tsp,++idx);

        char b_tstamp[TIME_STAMP_MSG_SIZE]; 

        char b_idx[7];
        int i_tmp = sprintf(b_idx,"%d",idx);
        i_tmp  = sprintf(b_tstamp,"%"PRIu64
                                      ",%d",tx_tsp,idx);


        //original code 
	struct Message obj;
        memcpy(obj.data, b_tstamp,TIME_STAMP_MSG_SIZE);


	struct Message *msg;
	struct rte_ether_addr s_addr = {{0x14,0x02,0xEC,0x89,0x8D,0x24}};
	struct rte_ether_addr d_addr = {{dst_mac_addr[0],dst_mac_addr[1],dst_mac_addr[2],dst_mac_addr[3],dst_mac_addr[4],dst_mac_addr[5]}};

	//uint16_t ether_type  = htons(0x0a00);//129;//rte_cpu_to_be_16(RTE_ETHER_TYPE_IPV4);//0x0800;//0x0a00;
        uint16_t ether_type = 0xb62c;//htons(0xb62c);
        debug0("\nether_type=%"PRIu64,ether_type);

        int BURST_SIZE = pkt_size;


        struct rte_mbuf *m;
	int i;
	for(i=0;i<BURST_SIZE;i++) {
		pkt[i] = rte_pktmbuf_alloc(l2fwd_pktmbuf_pool);
		eth_hdr = rte_pktmbuf_mtod(pkt[i],struct rte_ether_hdr*);
		eth_hdr->d_addr = d_addr;
		eth_hdr->s_addr = s_addr;
		eth_hdr->ether_type = ether_type;
		msg = (struct Message*) (rte_pktmbuf_mtod(pkt[i],char*) + sizeof(struct rte_ether_hdr));
		*msg = obj;
		int pkt_size = sizeof(struct Message) + sizeof(struct rte_ether_hdr);
		pkt[i]->data_len = pkt_size;
		pkt[i]->pkt_len = pkt_size;


                /* vlan ethernet type 802.1q */
		/* we create TSN packet using Vlan tag with highest priority */

		struct rte_vlan_hdr *vh;
		// Priority code point 7 (highest), 0 (default) 
		uint16_t vlan_priority = 3; 
		uint16_t vlan_id = VLAN_ID;
                uint16_t vlan_tag = (vlan_priority << 13) | vlan_id;
                uint16_t vlan_tag_be = rte_cpu_to_be_16(vlan_tag);
		struct rte_ether_hdr *oh, *nh;

		oh = rte_pktmbuf_mtod(pkt[i], struct rte_ether_hdr *);

		nh = (struct rte_ether_hdr *)rte_pktmbuf_prepend(pkt[i], sizeof(struct rte_vlan_hdr));
		memmove(nh, oh, 2 * RTE_ETHER_ADDR_LEN);
		nh->ether_type = rte_cpu_to_be_16(RTE_ETHER_TYPE_VLAN);

		vh = (struct rte_vlan_hdr *) (nh + 1);
		vh->vlan_tci = vlan_tag_be;

		pkt[i]->pkt_len = pkt_size + sizeof(struct rte_vlan_hdr);


	}


       debug0("\nSending Packet (Timestamp:%s) SRC:%02X:%02X:%02X:%02X:%02X:%02X DST:%02X:%02X:%02X:%02X:%02X:%02X\n",
                                msg->data, 
                                eth_hdr->s_addr.addr_bytes[0],
                                eth_hdr->s_addr.addr_bytes[1],
                                eth_hdr->s_addr.addr_bytes[2],
                                eth_hdr->s_addr.addr_bytes[3],
                                eth_hdr->s_addr.addr_bytes[4],
                                eth_hdr->s_addr.addr_bytes[5],
                                eth_hdr->d_addr.addr_bytes[0],
                                eth_hdr->d_addr.addr_bytes[1],
                                eth_hdr->d_addr.addr_bytes[2],
                                eth_hdr->d_addr.addr_bytes[3],
                                eth_hdr->d_addr.addr_bytes[4],
                                eth_hdr->d_addr.addr_bytes[5]
                                );

        return 0;

}

static uint64_t get_time_sec(clockid_t clkid)
{


	struct timespec now;

	clock_gettime(clkid, &now);
	return now.tv_sec * NSEC_PER_SEC;
}


/* main processing loop */

static int iCnt =0;
static void
talker_main_loop(void)
{

#define TIME_STAMP_MSG_SIZE 36

	struct rte_mbuf *pkts_burst[MAX_PKT_BURST];
	struct rte_mbuf *m;
	int sent, pkt_interval_ns=0;
	unsigned lcore_id;
	uint64_t prev_tsc, diff_tsc, cur_tsc, timer_tsc;
	unsigned i, j, portid, nb_rx;
	struct lcore_queue_conf *qconf;
	const uint64_t drain_tsc = (rte_get_tsc_hz() + US_PER_S - 1) / US_PER_S *
			BURST_TX_DRAIN_US;
	struct rte_eth_dev_tx_buffer *buffer;
        

	prev_tsc = 0;
	timer_tsc = 0;

	lcore_id = rte_lcore_id();
	qconf = &lcore_queue_conf[lcore_id];

	if (qconf->n_rx_port == 0) {
		RTE_LOG(INFO, L2FWD, "lcore %u has nothing to do\n", lcore_id);
		return;
	}

	RTE_LOG(INFO, L2FWD, "entering main loop on lcore %u\n", lcore_id);

	for (i = 0; i < qconf->n_rx_port; i++) {

		portid = qconf->rx_port_list[i];
		RTE_LOG(INFO, L2FWD, " -- lcoreid=%u portid=%u\n", lcore_id,
			portid);

	}

        int icounter = 0;
        sleep(1);

//debug
uint64_t tx_timestamp;
tx_timestamp = get_time_sec(CLOCK_REALTIME);    //0.5s ahead (stmmac limitation)
tx_timestamp += 100000;//opt->offset_ns;
tx_timestamp += 2 * NSEC_PER_SEC;

	while (!force_quit) {

            
//tx_timestamp += 2000000;//opt->interval_ns;
//debug

         //struct timespec ts;
         //uint64_t sleep_timestamp;
         //sleep_timestamp = tx_timestamp;
 	 //ts.tv_sec = sleep_timestamp / NSEC_PER_SEC;
	 //ts.tv_nsec = sleep_timestamp % NSEC_PER_SEC;
	 //clock_nanosleep(CLOCK_REALTIME, TIMER_ABSTIME, &ts, NULL);
         // fprintf(stdout, "\nsleep time:tv_sec=%ld tv_nsec=%ld",ts.tv_sec,ts.tv_nsec);
         pkt_interval_ns = pkt_interval * 1000;  
         usleep(pkt_interval_ns); 
         //cur_tsc = rte_rdtsc();
 

//debug
        if (icounter++ >= 100000){
             force_quit = true;
        }

        int BURST_SIZE = 1; 
        struct rte_mbuf *pkt[BURST_SIZE];
        int ret01 = construct_packet(pkt, BURST_SIZE);
        uint16_t nb_tx = rte_eth_tx_burst(0,0,pkt,BURST_SIZE);

        for (i = 0; i < qconf->n_rx_port; i++) {
				portid = l2fwd_dst_ports[qconf->rx_port_list[i]];
				buffer = tx_buffer[portid];

				sent = rte_eth_tx_buffer_flush(portid, 0, buffer);
				if (sent)
					port_statistics[portid].tx += sent;
	}


        for(i=0;i<BURST_SIZE;i++)
		rte_pktmbuf_free(pkt[i]);


        if (is_debug==0){
              printf("\r                ");
              printf("\rPacket sent: %d",++iCnt);
        }



   }

}

static int
talker_launch_one_lcore(__rte_unused void *dummy)
{
	talker_main_loop();
	return 0;
}

/* display usage */
static void
talker_usage(const char *prgname)
{
	printf("%s [EAL options] -- -p PORTMASK [-q NQ]\n"
	       "  -p PORTMASK: hexadecimal bitmask of ports to configure\n"
	       "  -q NQ: number of queue (=ports) per lcore (default is 1)\n"
	       "  -T PERIOD: packet will be transmit each PERIOD miliseconds (must >=2ms, 20ms by default)\n"
               "  -d Destination MAC address: use ':' format, for example, 08:00:27:cf:69:3e "
               "  -D [1,0] (1 to enable, 0 default disable) "
	       "  --[no-]mac-updating: Enable or disable MAC addresses updating (enabled by default)\n"
	       "      When enabled:\n"
	       "       - The source MAC address is replaced by the TX port MAC address\n"
	       "       - The destination MAC address is replaced by 02:00:00:00:00:TX_PORT_ID\n"
	       "  --portmap: Configure forwarding port pair mapping\n"
	       "	      Default: alternate port pairs\n\n",
	       prgname);
}

static int
talker_parse_portmask(const char *portmask)
{
	char *end = NULL;
	unsigned long pm;

	/* parse hexadecimal string */
	pm = strtoul(portmask, &end, 16);
	if ((portmask[0] == '\0') || (end == NULL) || (*end != '\0'))
		return 0;

	return pm;
}

static int
talker_parse_port_pair_config(const char *q_arg)
{
	enum fieldnames {
		FLD_PORT1 = 0,
		FLD_PORT2,
		_NUM_FLD
	};
	unsigned long int_fld[_NUM_FLD];
	const char *p, *p0 = q_arg;
	char *str_fld[_NUM_FLD];
	unsigned int size;
	char s[256];
	char *end;
	int i;

	nb_port_pair_params = 0;

	while ((p = strchr(p0, '(')) != NULL) {
		++p;
		p0 = strchr(p, ')');
		if (p0 == NULL)
			return -1;

		size = p0 - p;
		if (size >= sizeof(s))
			return -1;

		memcpy(s, p, size);
		s[size] = '\0';
		if (rte_strsplit(s, sizeof(s), str_fld,
				 _NUM_FLD, ',') != _NUM_FLD)
			return -1;
		for (i = 0; i < _NUM_FLD; i++) {
			errno = 0;
			int_fld[i] = strtoul(str_fld[i], &end, 0);
			if (errno != 0 || end == str_fld[i] ||
			    int_fld[i] >= RTE_MAX_ETHPORTS)
				return -1;
		}
		if (nb_port_pair_params >= RTE_MAX_ETHPORTS/2) {
			printf("exceeded max number of port pair params: %hu\n",
				nb_port_pair_params);
			return -1;
		}
		port_pair_params_array[nb_port_pair_params].port[0] =
				(uint16_t)int_fld[FLD_PORT1];
		port_pair_params_array[nb_port_pair_params].port[1] =
				(uint16_t)int_fld[FLD_PORT2];
		++nb_port_pair_params;
	}
	port_pair_params = port_pair_params_array;
	return 0;
}

static unsigned int
talker_parse_nqueue(const char *q_arg)
{
	char *end = NULL;
	unsigned long n;

	/* parse hexadecimal string */
	n = strtoul(q_arg, &end, 10);
	if ((q_arg[0] == '\0') || (end == NULL) || (*end != '\0'))
		return 0;
	if (n == 0)
		return 0;
	if (n >= MAX_RX_QUEUE_PER_LCORE)
		return 0;

	return n;
}

static int
talker_parse_packet_interval(const char *q_arg)
{
	char *end = NULL;
	int n;

	/* parse number string */
	n = strtol(q_arg, &end, 10);
	if ((q_arg[0] == '\0') || (end == NULL) || (*end != '\0'))
		return -1;
	if (n >= MAX_TIMER_PERIOD)
		return -1;

	return n;
}

static int 
talker_parse_dst_mac(const char *q_arg)
{

  int n = -5;

  char dst_mac_str[] = "000000000000";
  for (int i =0,j=0; i <17; i++)
  {
     if (q_arg[i] != ':')
       dst_mac_str[j++] = q_arg[i];
     else if (q_arg[i] == ':')
       n++;

  }

  char dummy[3] = "00";
  int j = 0;
  uint8_t num = 0;
  for(int k=0;k<6;k++)
  {
        for(int i=0;i<2;i++)
            dummy[i] = dst_mac_str[i+j];
        num = strtol(dummy, NULL, 16);
        j=j+2;
        dst_mac_addr[k] = num;
  }

  return n;
}

static int
l2fwd_parse_debug(const char *q_arg)
{
	if (*q_arg == '1')
             is_debug = 1;
	else
	     is_debug = 0;

        return 1;
}

static const char short_options[] =
	"p:"  /* portmask */
	"q:"  /* number of queues */
	"T:"  /* packet sent interval  */
        "d:"  /* destination mac adddress */ 
        "D:"  /*debug mode*/
	;

#define CMD_LINE_OPT_MAC_UPDATING "mac-updating"
#define CMD_LINE_OPT_NO_MAC_UPDATING "no-mac-updating"
#define CMD_LINE_OPT_PORTMAP_CONFIG "portmap"

enum {
	/* long options mapped to a short option */

	/* first long only option value must be >= 256, so that we won't
	 * conflict with short options */
	CMD_LINE_OPT_MIN_NUM = 256,
	CMD_LINE_OPT_PORTMAP_NUM,
};

static const struct option lgopts[] = {
	{ CMD_LINE_OPT_MAC_UPDATING, no_argument, &mac_updating, 1},
	{ CMD_LINE_OPT_NO_MAC_UPDATING, no_argument, &mac_updating, 0},
	{ CMD_LINE_OPT_PORTMAP_CONFIG, 1, 0, CMD_LINE_OPT_PORTMAP_NUM},
	{NULL, 0, 0, 0}
};

/* Parse the argument given in the command line of the application */
static int
talker_parse_args(int argc, char **argv)
{
	int opt, ret, interval_ms;
	char **argvopt;
	int option_index;
	char *prgname = argv[0];

	argvopt = argv;
	port_pair_params = NULL;

	while ((opt = getopt_long(argc, argvopt, short_options,
				  lgopts, &option_index)) != EOF) {

		switch (opt) {
		/* portmask */
		case 'p':
			l2fwd_enabled_port_mask = talker_parse_portmask(optarg);
			if (l2fwd_enabled_port_mask == 0) {
				printf("invalid portmask\n");
				talker_usage(prgname);
				return -1;
			}
			break;

		/* nqueue */
		case 'q':
			l2fwd_rx_queue_per_lcore = talker_parse_nqueue(optarg);
			if (l2fwd_rx_queue_per_lcore == 0) {
				printf("invalid queue number\n");
				talker_usage(prgname);
				return -1;
			}
			break;

		/* timer period */
		case 'T':
			interval_ms = talker_parse_packet_interval(optarg);
			if (interval_ms < 2) {
				printf("invalid packet interval\n");
				talker_usage(prgname);
				return -1;
			}
			pkt_interval = interval_ms;
			break;

                /* packet destination MAC address  */
		case 'd':
                      ret  = talker_parse_dst_mac(optarg);
                      if (ret){
				printf("invalid destination mac address, please use format as described (e.g. -d 08:00:1B:1A:12:A3)\n");
				talker_usage(prgname);
				return -1;


		      }
                      break;

                /*debug option*/ 
                case 'D':
                        ret = l2fwd_parse_debug(optarg);
			break;


                /* long options */
		case CMD_LINE_OPT_PORTMAP_NUM:
			ret = talker_parse_port_pair_config(optarg);
			if (ret) {
				fprintf(stderr, "Invalid config\n");
				talker_usage(prgname);
				return -1;
			}
			break;

		default:
			talker_usage(prgname);
			return -1;
		}
	}

	if (optind >= 0)
		argv[optind-1] = prgname;

	ret = optind-1;
	optind = 1; /* reset getopt lib */
	return ret;
}

/*
 * Check port pair config with enabled port mask,
 * and for valid port pair combinations.
 */
static int
check_port_pair_config(void)
{
	uint32_t port_pair_config_mask = 0;
	uint32_t port_pair_mask = 0;
	uint16_t index, i, portid;

	for (index = 0; index < nb_port_pair_params; index++) {
		port_pair_mask = 0;

		for (i = 0; i < NUM_PORTS; i++)  {
			portid = port_pair_params[index].port[i];
			if ((l2fwd_enabled_port_mask & (1 << portid)) == 0) {
				printf("port %u is not enabled in port mask\n",
				       portid);
				return -1;
			}
			if (!rte_eth_dev_is_valid_port(portid)) {
				printf("port %u is not present on the board\n",
				       portid);
				return -1;
			}

			port_pair_mask |= 1 << portid;
		}

		if (port_pair_config_mask & port_pair_mask) {
			printf("port %u is used in other port pairs\n", portid);
			return -1;
		}
		port_pair_config_mask |= port_pair_mask;
	}

	l2fwd_enabled_port_mask &= port_pair_config_mask;

	return 0;
}

/* Check the link status of all ports in up to 9s, and print them finally */
static void
check_all_ports_link_status(uint32_t port_mask)
{
#define CHECK_INTERVAL 100 /* 100ms */
#define MAX_CHECK_TIME 90 /* 9s (90 * 100ms) in total */
	uint16_t portid;
	uint8_t count, all_ports_up, print_flag = 0;
	struct rte_eth_link link;
	int ret;
	char link_status_text[RTE_ETH_LINK_MAX_STR_LEN];

	printf("\nChecking link status");
	fflush(stdout);
	for (count = 0; count <= MAX_CHECK_TIME; count++) {
		if (force_quit)
			return;
		all_ports_up = 1;
		RTE_ETH_FOREACH_DEV(portid) {
			if (force_quit)
				return;
			if ((port_mask & (1 << portid)) == 0)
				continue;
			memset(&link, 0, sizeof(link));
			ret = rte_eth_link_get_nowait(portid, &link);
			if (ret < 0) {
				all_ports_up = 0;
				if (print_flag == 1)
					printf("Port %u link get failed: %s\n",
						portid, rte_strerror(-ret));
				continue;
			}
			/* print link status if flag set */
			if (print_flag == 1) {
				rte_eth_link_to_str(link_status_text,
					sizeof(link_status_text), &link);
				printf("Port %d %s\n", portid,
				       link_status_text);
				continue;
			}
			/* clear all_ports_up flag if any link down */
			if (link.link_status == ETH_LINK_DOWN) {
				all_ports_up = 0;
				break;
			}
		}
		/* after finally printing all link status, get out */
		if (print_flag == 1)
			break;

		if (all_ports_up == 0) {
			printf(".");
			fflush(stdout);
			rte_delay_ms(CHECK_INTERVAL);
		}

		/* set the print_flag if all ports up or timeout */
		if (all_ports_up == 1 || count == (MAX_CHECK_TIME - 1)) {
			print_flag = 1;
			printf("done\n");
		}
	}
}

static void
signal_handler(int signum)
{
	if (signum == SIGINT || signum == SIGTERM) {
		printf("\n\nSignal %d received, preparing to exit...\n",
				signum);
		force_quit = true;
	}
}

int
main(int argc, char **argv)
{
	struct lcore_queue_conf *qconf;
	int ret;
	uint16_t nb_ports;
	uint16_t nb_ports_available = 0;
	uint16_t portid, last_port;
	unsigned lcore_id, rx_lcore_id;
	unsigned nb_ports_in_mask = 0;
	unsigned int nb_lcores = 0;
	unsigned int nb_mbufs;

	/* init EAL */
	ret = rte_eal_init(argc, argv);
	if (ret < 0)
		rte_exit(EXIT_FAILURE, "Invalid EAL arguments\n");
	argc -= ret;
	argv += ret;

	force_quit = false;
	signal(SIGINT, signal_handler);
	signal(SIGTERM, signal_handler);

	/* parse application arguments (after the EAL ones) */
	ret = talker_parse_args(argc, argv);
	if (ret < 0)
		rte_exit(EXIT_FAILURE, "Invalid Talker arguments %d\n",ret);

	printf("MAC updating %s\n", mac_updating ? "enabled" : "disabled");


	nb_ports = rte_eth_dev_count_avail();
	if (nb_ports == 0)
		rte_exit(EXIT_FAILURE, "No Ethernet ports - bye\n");

	if (port_pair_params != NULL) {
		if (check_port_pair_config() < 0)
			rte_exit(EXIT_FAILURE, "Invalid port pair config\n");
	}

	/* check port mask to possible port mask */
	if (l2fwd_enabled_port_mask & ~((1 << nb_ports) - 1))
		rte_exit(EXIT_FAILURE, "Invalid portmask; possible (0x%x)\n",
			(1 << nb_ports) - 1);

	/* reset l2fwd_dst_ports */
	for (portid = 0; portid < RTE_MAX_ETHPORTS; portid++)
		l2fwd_dst_ports[portid] = 0;
	last_port = 0;

	/* populate destination port details */
	if (port_pair_params != NULL) {
		uint16_t idx, p;

		for (idx = 0; idx < (nb_port_pair_params << 1); idx++) {
			p = idx & 1;
			portid = port_pair_params[idx >> 1].port[p];
			l2fwd_dst_ports[portid] =
				port_pair_params[idx >> 1].port[p ^ 1];
		}
	} else {
		RTE_ETH_FOREACH_DEV(portid) {
			/* skip ports that are not enabled */
			if ((l2fwd_enabled_port_mask & (1 << portid)) == 0)
				continue;

			if (nb_ports_in_mask % 2) {
				l2fwd_dst_ports[portid] = last_port;
				l2fwd_dst_ports[last_port] = portid;
			} else {
				last_port = portid;
			}

			nb_ports_in_mask++;
		}
		if (nb_ports_in_mask % 2) {
			printf("Notice: odd number of ports in portmask.\n");
			l2fwd_dst_ports[last_port] = last_port;
		}
	}

	rx_lcore_id = 0;
	qconf = NULL;

	/* Initialize the port/queue configuration of each logical core */
	RTE_ETH_FOREACH_DEV(portid) {
		/* skip ports that are not enabled */
		if ((l2fwd_enabled_port_mask & (1 << portid)) == 0)
			continue;

		/* get the lcore_id for this port */
		while (rte_lcore_is_enabled(rx_lcore_id) == 0 ||
		       lcore_queue_conf[rx_lcore_id].n_rx_port ==
		       l2fwd_rx_queue_per_lcore) {
			rx_lcore_id++;
			if (rx_lcore_id >= RTE_MAX_LCORE)
				rte_exit(EXIT_FAILURE, "Not enough cores\n");
		}

		if (qconf != &lcore_queue_conf[rx_lcore_id]) {
			/* Assigned a new logical core in the loop above. */
			qconf = &lcore_queue_conf[rx_lcore_id];
			nb_lcores++;
		}

		qconf->rx_port_list[qconf->n_rx_port] = portid;
		qconf->n_rx_port++;
		printf("Lcore %u: RX port %u TX port %u\n", rx_lcore_id,
		       portid, l2fwd_dst_ports[portid]);
	}
 
	nb_mbufs = RTE_MAX(nb_ports * (nb_rxd + nb_txd + MAX_PKT_BURST +
		nb_lcores * MEMPOOL_CACHE_SIZE), 8192U);

	/* create the mbuf pool */
	l2fwd_pktmbuf_pool = rte_pktmbuf_pool_create("mbuf_pool", nb_mbufs,
		MEMPOOL_CACHE_SIZE, 0, RTE_MBUF_DEFAULT_BUF_SIZE,
		rte_socket_id());
	if (l2fwd_pktmbuf_pool == NULL)
		rte_exit(EXIT_FAILURE, "Cannot init mbuf pool\n");

	/* Initialise each port */
	RTE_ETH_FOREACH_DEV(portid) {
		struct rte_eth_rxconf rxq_conf;
		struct rte_eth_txconf txq_conf;
		struct rte_eth_conf local_port_conf = port_conf;
		struct rte_eth_dev_info dev_info;

		/* skip ports that are not enabled */
		if ((l2fwd_enabled_port_mask & (1 << portid)) == 0) {
			printf("Skipping disabled port %u\n", portid);
			continue;
		}
		nb_ports_available++;

		/* init port */
		printf("Initializing port %u... ", portid);
		fflush(stdout);

		ret = rte_eth_dev_info_get(portid, &dev_info);
		if (ret != 0)
			rte_exit(EXIT_FAILURE,
				"Error during getting device (port %u) info: %s\n",
				portid, strerror(-ret));

		if (dev_info.tx_offload_capa & DEV_TX_OFFLOAD_MBUF_FAST_FREE)
			local_port_conf.txmode.offloads |=
				DEV_TX_OFFLOAD_MBUF_FAST_FREE;
		ret = rte_eth_dev_configure(portid, 1, 1, &local_port_conf);
		if (ret < 0)
			rte_exit(EXIT_FAILURE, "Cannot configure device: err=%d, port=%u\n",
				  ret, portid);

		ret = rte_eth_dev_adjust_nb_rx_tx_desc(portid, &nb_rxd,
						       &nb_txd);
		if (ret < 0)
			rte_exit(EXIT_FAILURE,
				 "Cannot adjust number of descriptors: err=%d, port=%u\n",
				 ret, portid);

		ret = rte_eth_macaddr_get(portid,
					  &l2fwd_ports_eth_addr[portid]);
		if (ret < 0)
			rte_exit(EXIT_FAILURE,
				 "Cannot get MAC address: err=%d, port=%u\n",
				 ret, portid);

		/* init one RX queue */
		fflush(stdout);
		rxq_conf = dev_info.default_rxconf;
		rxq_conf.offloads = local_port_conf.rxmode.offloads;
		ret = rte_eth_rx_queue_setup(portid, 0, nb_rxd,
					     rte_eth_dev_socket_id(portid),
					     &rxq_conf,
					     l2fwd_pktmbuf_pool);
		if (ret < 0)
			rte_exit(EXIT_FAILURE, "rte_eth_rx_queue_setup:err=%d, port=%u\n",
				  ret, portid);

		/* init one TX queue on each port */
		fflush(stdout);
		txq_conf = dev_info.default_txconf;
		txq_conf.offloads = local_port_conf.txmode.offloads;
		ret = rte_eth_tx_queue_setup(portid, 0, nb_txd,
				rte_eth_dev_socket_id(portid),
				&txq_conf);
		if (ret < 0)
			rte_exit(EXIT_FAILURE, "rte_eth_tx_queue_setup:err=%d, port=%u\n",
				ret, portid);

		/* Initialize TX buffers */
		tx_buffer[portid] = rte_zmalloc_socket("tx_buffer",
				RTE_ETH_TX_BUFFER_SIZE(MAX_PKT_BURST), 0,
				rte_eth_dev_socket_id(portid));
		if (tx_buffer[portid] == NULL)
			rte_exit(EXIT_FAILURE, "Cannot allocate buffer for tx on port %u\n",
					portid);

		rte_eth_tx_buffer_init(tx_buffer[portid], MAX_PKT_BURST);

		ret = rte_eth_tx_buffer_set_err_callback(tx_buffer[portid],
				rte_eth_tx_buffer_count_callback,
				&port_statistics[portid].dropped);
		if (ret < 0)
			rte_exit(EXIT_FAILURE,
			"Cannot set error callback for tx buffer on port %u\n",
				 portid);

		ret = rte_eth_dev_set_ptypes(portid, RTE_PTYPE_UNKNOWN, NULL,
					     0);
		if (ret < 0)
			printf("Port %u, Failed to disable Ptype parsing\n",
					portid);
		/* Start device */
		ret = rte_eth_dev_start(portid);
		if (ret < 0)
			rte_exit(EXIT_FAILURE, "rte_eth_dev_start:err=%d, port=%u\n",
				  ret, portid);

		ret = rte_eth_promiscuous_enable(portid);
		if (ret != 0)
			rte_exit(EXIT_FAILURE,
				 "rte_eth_promiscuous_enable:err=%s, port=%u\n",
				 rte_strerror(-ret), portid);

		printf("Port %u, MAC address: %02X:%02X:%02X:%02X:%02X:%02X\n\n",
				portid,
				l2fwd_ports_eth_addr[portid].addr_bytes[0],
				l2fwd_ports_eth_addr[portid].addr_bytes[1],
				l2fwd_ports_eth_addr[portid].addr_bytes[2],
				l2fwd_ports_eth_addr[portid].addr_bytes[3],
				l2fwd_ports_eth_addr[portid].addr_bytes[4],
				l2fwd_ports_eth_addr[portid].addr_bytes[5]);

		/* initialize port stats */
		memset(&port_statistics, 0, sizeof(port_statistics));
	}

	if (!nb_ports_available) {
		rte_exit(EXIT_FAILURE,
			"All available ports are disabled. Please set portmask.\n");
	}

	check_all_ports_link_status(l2fwd_enabled_port_mask);


	ret = 0;
	/* launch per-lcore init on every lcore */
	rte_eal_mp_remote_launch(talker_launch_one_lcore, NULL, CALL_MAIN);
	RTE_LCORE_FOREACH_WORKER(lcore_id) {
		if (rte_eal_wait_lcore(lcore_id) < 0) {
			ret = -1;
			break;
		}
	}


        //struct rte_eth_stats eth_stats;
	RTE_ETH_FOREACH_DEV(portid) {
		if ((l2fwd_enabled_port_mask & (1 << portid)) == 0)
			continue;

		printf("Closing port %d...", portid);
		ret = rte_eth_dev_stop(portid);
		if (ret != 0)
			printf("rte_eth_dev_stop: err=%d, port=%d\n",
			       ret, portid);
		rte_eth_dev_close(portid);
	}


	printf("\nBye...\n");

	return ret;
}

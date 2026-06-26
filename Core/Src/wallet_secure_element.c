#include "wallet_secure_element.h"

#include "main.h"
#include "libtropic.h"
#include "libtropic_port_stm32u5xx.h"

#include <stdint.h>
#include <string.h>

/*
 * Real TROPIC01 smoke-check layer.
 *
 * This does NOT make TROPIC01 do Bitcoin secp256k1 signing yet.
 * It proves the STM32 can talk to TROPIC01 through libtropic before
 * wallet_key_provider.c releases the current regtest dev key.
 */

extern RNG_HandleTypeDef hrng;

volatile int wallet_secure_element_init_ret = 999;
volatile int wallet_secure_element_authorize_ret = 999;
volatile uint32_t wallet_secure_element_auth_count = 0;

volatile int wallet_secure_element_lt_init_ret = 999;
volatile int wallet_secure_element_lt_mode_ret = 999;
volatile int wallet_secure_element_lt_chip_id_ret = 999;
volatile int wallet_secure_element_lt_deinit_ret = 999;
volatile uint32_t wallet_secure_element_mode_value = 0;
volatile uint32_t wallet_secure_element_initialized = 0;

volatile uint32_t wallet_secure_element_init_attempts = 0;
volatile int wallet_secure_element_last_attempt_ret = 999;


static lt_handle_t wallet_secure_element_handle;
static lt_dev_stm32u5xx_t wallet_secure_element_device;

static void wallet_secure_element_configure_device(void)
{
    memset(&wallet_secure_element_device, 0, sizeof(wallet_secure_element_device));

    /*
     * TROPIC01 wiring:
     *   SPI1 SCK  = PA5
     *   SPI1 MISO = PA6
     *   SPI1 MOSI = PA7
     *   TROPIC CS = PD14
     */
    wallet_secure_element_device.spi_instance = SPI1;
    wallet_secure_element_device.baudrate_prescaler = SPI_BAUDRATEPRESCALER_64;
    wallet_secure_element_device.spi_cs_gpio_bank = GPIOD;
    wallet_secure_element_device.spi_cs_gpio_pin = GPIO_PIN_14;
    wallet_secure_element_device.rng_handle = &hrng;

    /*
     * Critical:
     * libtropic's STM32 port reads h->l2.device inside lt_port_init().
     * If this is not set before lt_init(), the board HardFaults.
     */
    wallet_secure_element_handle.l2.device = &wallet_secure_element_device;
}




int wallet_secure_element_init(void)
{
    lt_tr01_mode_t mode;
    struct lt_chip_id_t chip_id;

    const uint32_t max_attempts = 8U;

    wallet_secure_element_init_ret = 999;
    wallet_secure_element_authorize_ret = 999;
    wallet_secure_element_auth_count = 0;

    wallet_secure_element_lt_init_ret = 999;
    wallet_secure_element_lt_mode_ret = 999;
    wallet_secure_element_lt_chip_id_ret = 999;
    wallet_secure_element_lt_deinit_ret = 999;
    wallet_secure_element_mode_value = 0;
    wallet_secure_element_initialized = 0;

    wallet_secure_element_init_attempts = 0;
    wallet_secure_element_last_attempt_ret = 999;

    /*
     * Give TROPIC01 time after MCU reset / debugger attach / COM-port toggling.
     */
    HAL_Delay(250);

    for (uint32_t attempt = 1U; attempt <= max_attempts; attempt++)
    {
        wallet_secure_element_init_attempts = attempt;
        wallet_secure_element_last_attempt_ret = 999;

        memset(&wallet_secure_element_handle, 0, sizeof(wallet_secure_element_handle));
        memset(&chip_id, 0, sizeof(chip_id));
        memset(&mode, 0, sizeof(mode));

        wallet_secure_element_configure_device();

        /*
         * Extra settle time between attempts.
         */
        HAL_Delay(100);

        wallet_secure_element_lt_init_ret =
            (int)lt_init(&wallet_secure_element_handle);

        if (wallet_secure_element_lt_init_ret != (int)LT_OK)
        {
            wallet_secure_element_last_attempt_ret = -100;
            wallet_secure_element_init_ret = -100;
            HAL_Delay(200);
            continue;
        }

        wallet_secure_element_lt_mode_ret =
            (int)lt_get_tr01_mode(&wallet_secure_element_handle, &mode);

        if (wallet_secure_element_lt_mode_ret != (int)LT_OK)
        {
            wallet_secure_element_lt_deinit_ret =
                (int)lt_deinit(&wallet_secure_element_handle);

            wallet_secure_element_last_attempt_ret = -101;
            wallet_secure_element_init_ret = -101;
            HAL_Delay(200);
            continue;
        }

        wallet_secure_element_mode_value = (uint32_t)mode;

        wallet_secure_element_lt_chip_id_ret =
            (int)lt_get_info_chip_id(&wallet_secure_element_handle, &chip_id);

        if (wallet_secure_element_lt_chip_id_ret != (int)LT_OK)
        {
            wallet_secure_element_lt_deinit_ret =
                (int)lt_deinit(&wallet_secure_element_handle);

            wallet_secure_element_last_attempt_ret = -102;
            wallet_secure_element_init_ret = -102;
            HAL_Delay(200);
            continue;
        }

        wallet_secure_element_initialized = 1;
        wallet_secure_element_last_attempt_ret = 0;
        wallet_secure_element_init_ret = 0;

        return 0;
    }

    return wallet_secure_element_init_ret;
}






int wallet_secure_element_authorize_key_use(void)
{
    lt_tr01_mode_t mode;

    if (wallet_secure_element_initialized != 1U)
    {
        wallet_secure_element_authorize_ret = -1;
        return -1;
    }

    memset(&mode, 0, sizeof(mode));

    wallet_secure_element_lt_mode_ret =
        (int)lt_get_tr01_mode(&wallet_secure_element_handle, &mode);

    if (wallet_secure_element_lt_mode_ret != (int)LT_OK)
    {
        wallet_secure_element_authorize_ret = -2;
        return -2;
    }

    wallet_secure_element_mode_value = (uint32_t)mode;

    wallet_secure_element_auth_count++;
    wallet_secure_element_authorize_ret = 0;

    return 0;
}


static void wallet_secure_element_hex_append(char *out,
                                             uint32_t out_size,
                                             uint32_t *off,
                                             const uint8_t *data,
                                             uint32_t data_len)
{
    static const char hex[] = "0123456789abcdef";

    if (out == NULL || off == NULL || data == NULL || out_size == 0U)
    {
        return;
    }

    for (uint32_t i = 0; i < data_len; i++)
    {
        if ((*off + 2U) >= out_size)
        {
            break;
        }

        out[*off] = hex[(data[i] >> 4) & 0x0FU];
        (*off)++;
        out[*off] = hex[data[i] & 0x0FU];
        (*off)++;
    }

    if (*off < out_size)
    {
        out[*off] = '\0';
    }
}

int wallet_secure_element_p256_selftest(char *out, uint32_t out_size)
{
    static const uint8_t test_hash[32] = {
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
        0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa, 0x99, 0x88,
        0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00
    };

    uint8_t pubkey[TR01_CURVE_P256_PUBKEY_LEN];
    uint8_t sig[TR01_ECDSA_EDDSA_SIGNATURE_LENGTH];
    lt_ecc_curve_type_t curve = 0;
    lt_ecc_key_origin_t origin = 0;

    int init_ret = wallet_secure_element_init();

    lt_ret_t erase_before_ret = LT_OK;
    lt_ret_t gen_ret = LT_L3_FAIL;
    lt_ret_t read_ret = LT_L3_FAIL;
    lt_ret_t sign_ret = LT_L3_FAIL;
    lt_ret_t erase_after_ret = LT_L3_FAIL;

    memset(pubkey, 0, sizeof(pubkey));
    memset(sig, 0, sizeof(sig));

    if (init_ret == 0)
    {
        erase_before_ret = lt_ecc_key_erase(&wallet_secure_element_handle, TR01_ECC_SLOT_31);

        gen_ret = lt_ecc_key_generate(&wallet_secure_element_handle,
                                      TR01_ECC_SLOT_31,
                                      TR01_CURVE_P256);

        if (gen_ret == LT_OK)
        {
            read_ret = lt_ecc_key_read(&wallet_secure_element_handle,
                                       TR01_ECC_SLOT_31,
                                       pubkey,
                                       sizeof(pubkey),
                                       &curve,
                                       &origin);
        }

        if (gen_ret == LT_OK)
        {
            sign_ret = lt_ecc_ecdsa_sign(&wallet_secure_element_handle,
                                         TR01_ECC_SLOT_31,
                                         test_hash,
                                         sizeof(test_hash),
                                         sig);
        }

        erase_after_ret = lt_ecc_key_erase(&wallet_secure_element_handle, TR01_ECC_SLOT_31);
    }

    int pass = ((init_ret == 0) &&
                (gen_ret == LT_OK) &&
                (read_ret == LT_OK) &&
                (sign_ret == LT_OK));

    uint32_t off = 0U;

    if (out != NULL && out_size > 0U)
    {
        int n = snprintf(out,
                         out_size,
                         "\r\n%s\r\n"
                         "TEST=TROPIC_P256_SIGN_SELFTEST\r\n"
                         "SLOT=31\r\n"
                         "CURVE=P256\r\n"
                         "INIT_RET=%d\r\n"
                         "ERASE_BEFORE_RET=%d\r\n"
                         "GEN_RET=%d\r\n"
                         "READ_RET=%d\r\n"
                         "SIGN_RET=%d\r\n"
                         "ERASE_AFTER_RET=%d\r\n"
                         "READ_CURVE=%d\r\n"
                         "READ_ORIGIN=%d\r\n"
                         "BITCOIN_DIRECT_TROPIC_SIGNING=0\r\n"
                         "BITCOIN_REQUIRED_CURVE=SECP256K1\r\n"
                         "TROPIC_SELFTEST_CURVE=P256\r\n",
                         pass ? "OK SEKEYTEST" : "ERR SEKEYTEST",
                         init_ret,
                         (int)erase_before_ret,
                         (int)gen_ret,
                         (int)read_ret,
                         (int)sign_ret,
                         (int)erase_after_ret,
                         (int)curve,
                         (int)origin);

        if (n < 0)
        {
            out[0] = '\0';
            off = 0U;
        }
        else
        {
            off = (uint32_t)n;
            if (off >= out_size)
            {
                off = out_size - 1U;
            }
        }

        if (read_ret == LT_OK)
        {
            if ((off + 12U) < out_size)
            {
                off += (uint32_t)snprintf(&out[off], out_size - off, "PUBKEY_XY=");
                wallet_secure_element_hex_append(out, out_size, &off, pubkey, sizeof(pubkey));
                if ((off + 2U) < out_size)
                {
                    out[off++] = '\r';
                    out[off++] = '\n';
                    out[off] = '\0';
                }
            }
        }

        if (sign_ret == LT_OK)
        {
            if ((off + 8U) < out_size)
            {
                off += (uint32_t)snprintf(&out[off], out_size - off, "SIG_RS=");
                wallet_secure_element_hex_append(out, out_size, &off, sig, sizeof(sig));
                if ((off + 2U) < out_size)
                {
                    out[off++] = '\r';
                    out[off++] = '\n';
                    out[off] = '\0';
                }
            }
        }
    }

    return pass ? 0 : -1;
}

